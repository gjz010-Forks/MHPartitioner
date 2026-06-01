#!/usr/bin/env python3

from __future__ import annotations

import argparse
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CIRCUITS_DIR = REPO_ROOT / "circuits"
DEFAULT_LOG_DIR = REPO_ROOT / ".circuit-smoke"
DEFAULT_COMPILED_DIR = REPO_ROOT / ".compiled"
EXTRA_CASE_ARGS = {
    "withToffolis": ["-cc"],
}
INSUFFICIENT_QUBITS_RE = re.compile(
    r"There are not enough qubits to run the circuit\. Qubits required: (\d+)\."
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run smoke tests for the example circuits in circuits/."
    )
    parser.add_argument(
        "cases",
        nargs="*",
        help="Circuit file names under circuits/. Default: run all known files.",
    )
    parser.add_argument(
        "--binary",
        help="Path to the mhpartitioner/Main executable. Default: try cabal list-bin, then result/bin/mhpartitioner.",
    )
    parser.add_argument(
        "--circuits-dir",
        default=str(DEFAULT_CIRCUITS_DIR),
        help="Directory containing input circuit files.",
    )
    parser.add_argument(
        "--kahypar-root",
        default=os.environ.get("KAHYPAR_ROOT"),
        help="Root directory containing KaHyPar and kahypar/config/. Defaults to $KAHYPAR_ROOT.",
    )
    parser.add_argument(
        "--k",
        type=int,
        default=2,
        help="Number of QPUs to request for each run. Default: 2.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Per-case timeout in seconds. Default: 300.",
    )
    parser.add_argument(
        "--output-format",
        choices=["gatecount", "ascii"],
        default="gatecount",
        help="Output format passed to Main via -o=. Use ascii to capture textual circuits in logs.",
    )
    parser.add_argument(
        "--log-dir",
        default=str(DEFAULT_LOG_DIR),
        help="Directory where stdout/stderr logs should be written.",
    )
    parser.add_argument(
        "--compiled-dir",
        help="Directory where compiled ASCII circuits should be written via Main -f=. One file per case.",
    )
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Stop after the first failure.",
    )
    return parser.parse_args()


def resolve_binary(explicit: str | None) -> Path:
    if explicit:
        binary = Path(explicit).expanduser().resolve()
        if not binary.is_file():
            raise SystemExit(f"Binary not found: {binary}")
        return binary

    try:
        result = subprocess.run(
            ["cabal", "list-bin", "exe:Main"],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        result = None

    if result is not None:
        binary = Path(result.stdout.strip()).resolve()
        if binary.is_file():
            return binary

    packaged = (REPO_ROOT / "result" / "bin" / "mhpartitioner").resolve()
    if packaged.is_file():
        return packaged

    raise SystemExit(
        "Could not resolve an executable. Pass --binary or build exe:Main/result/bin/mhpartitioner first."
    )


def normalize_kahypar_root(raw_root: str | None) -> str:
    if not raw_root:
        raise SystemExit("KAHYPAR_ROOT is not set. Export it or pass --kahypar-root.")

    root = Path(raw_root).expanduser().resolve()
    exe = root / "KaHyPar"
    config = root / "kahypar" / "config" / "km1_kKaHyPar_sea20.ini"
    if not exe.is_file():
        raise SystemExit(f"KaHyPar executable not found under {exe}")
    if not os.access(exe, os.X_OK):
        raise SystemExit(f"KaHyPar is not executable: {exe}")
    if not config.is_file():
        raise SystemExit(f"KaHyPar config not found under {config}")
    return str(root) + "/"


def discover_cases(circuits_dir: Path, requested: list[str]) -> list[Path]:
    if not circuits_dir.is_dir():
        raise SystemExit(f"Circuits directory not found: {circuits_dir}")

    available = {path.name: path for path in circuits_dir.iterdir() if path.is_file()}
    if requested:
        missing = [name for name in requested if name not in available]
        if missing:
            missing_text = ", ".join(sorted(missing))
            raise SystemExit(f"Unknown circuit(s): {missing_text}")
        return [available[name] for name in requested]
    return [available[name] for name in sorted(available)]


def count_qubits(circuit_path: Path) -> int:
    first_line = circuit_path.read_text(encoding="utf-8").splitlines()[0]
    qubits = first_line.count(":Qbit")
    if qubits < 1:
        raise SystemExit(f"Could not infer qubit count from {circuit_path}")
    return qubits


def build_case_args(
    circuit_path: Path,
    k: int,
    output_format: str,
    size: int,
    compiled_path: Path | None,
) -> tuple[int, list[str]]:
    qubits = count_qubits(circuit_path)
    args = [f"-k={k}", f"-s={size}", f"-o={output_format}", "-vb"]
    if compiled_path is not None:
        args.append(f"-f={compiled_path}")
    args.extend(EXTRA_CASE_ARGS.get(circuit_path.name, []))
    return qubits, args


def write_log(log_path: Path, stdout: str, stderr: str) -> None:
    payload = stdout
    if stderr:
        if payload and not payload.endswith("\n"):
            payload += "\n"
        payload += "[stderr]\n" + stderr
    log_path.write_text(payload, encoding="utf-8")


def required_qubits(stdout: str, stderr: str) -> int | None:
    combined = stdout + "\n" + stderr
    match = INSUFFICIENT_QUBITS_RE.search(combined)
    if match is None:
        return None
    return int(match.group(1))


def run_case(
    binary: Path,
    kahypar_root: str,
    circuit_path: Path,
    case_args_builder,
    timeout: int,
    log_dir: Path,
    output_format: str,
    compiled_path: Path | None,
) -> tuple[bool, float, Path, str]:
    log_path = log_dir / f"{circuit_path.name}.{output_format}.log"
    start = time.monotonic()

    size = case_args_builder["initial_size"]
    retried = False
    while True:
        _, case_args = build_case_args(
            circuit_path,
            case_args_builder["k"],
            output_format,
            size,
            compiled_path,
        )
        command = [str(binary), f"-d={kahypar_root}", *case_args]
        if compiled_path is not None and compiled_path.exists():
            compiled_path.unlink()

        try:
            with circuit_path.open("r", encoding="utf-8") as handle:
                result = subprocess.run(
                    command,
                    cwd=REPO_ROOT,
                    stdin=handle,
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                )
        except subprocess.TimeoutExpired as exc:
            elapsed = time.monotonic() - start
            stdout = exc.stdout or ""
            stderr = exc.stderr or ""
            write_log(log_path, stdout, stderr)
            return False, elapsed, log_path, f"timeout>{timeout}s"

        needed = required_qubits(result.stdout, result.stderr)
        if needed is not None and needed > case_args_builder["k"] * size and not retried:
            size = math.ceil(needed / case_args_builder["k"])
            retried = True
            continue

        elapsed = time.monotonic() - start
        write_log(log_path, result.stdout, result.stderr)
        if result.returncode != 0:
            return False, elapsed, log_path, f"exit={result.returncode}"
        if needed is not None:
            return False, elapsed, log_path, f"insufficient-qubits>{needed}"
        if compiled_path is not None and not compiled_path.is_file():
            return False, elapsed, log_path, "missing-compiled-output"

        detail = f"exit=0, s={size}"
        if retried:
            detail += " (retried)"
        return True, elapsed, log_path, detail


def main() -> int:
    args = parse_args()
    if args.k < 2:
        raise SystemExit("--k must be at least 2.")

    binary = resolve_binary(args.binary)
    kahypar_root = normalize_kahypar_root(args.kahypar_root)
    circuits_dir = Path(args.circuits_dir).expanduser().resolve()
    log_dir = Path(args.log_dir).expanduser().resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    compiled_dir = (
        Path(args.compiled_dir).expanduser().resolve() if args.compiled_dir else None
    )
    if compiled_dir is not None:
        compiled_dir.mkdir(parents=True, exist_ok=True)
    cases = discover_cases(circuits_dir, args.cases)

    print(f"Binary: {binary}")
    print(f"KAHYPAR_ROOT: {kahypar_root}")
    print(f"Log dir: {log_dir}")
    if compiled_dir is not None:
        print(f"Compiled dir: {compiled_dir}")
    print(f"Cases: {', '.join(path.name for path in cases)}")

    failures = 0
    for circuit_path in cases:
        initial_size = math.ceil(count_qubits(circuit_path) / args.k)
        compiled_path = (
            compiled_dir / f"{circuit_path.name}.out" if compiled_dir is not None else None
        )
        qubits, case_args = build_case_args(
            circuit_path,
            args.k,
            args.output_format,
            initial_size,
            compiled_path,
        )
        print(
            f"RUN {circuit_path.name}: qubits={qubits}, args={' '.join(case_args)}",
            flush=True,
        )
        ok, elapsed, log_path, detail = run_case(
            binary,
            kahypar_root,
            circuit_path,
            {"initial_size": initial_size, "k": args.k},
            args.timeout,
            log_dir,
            args.output_format,
            compiled_path,
        )
        status = "PASS" if ok else "FAIL"
        compiled_text = f", compiled={compiled_path}" if compiled_path is not None else ""
        print(
            f"{status} {circuit_path.name}: {detail}, {elapsed:.1f}s, log={log_path}{compiled_text}"
        )
        if not ok:
            failures += 1
            if args.fail_fast:
                break

    if failures:
        print(f"Summary: {len(cases) - failures} passed, {failures} failed.")
        return 1

    print(f"Summary: all {len(cases)} case(s) passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())