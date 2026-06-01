default:
    @just --list

build:
    cabal build exe:Main

smoke *cases: build
    uv run python3 scripts/run_circuits.py {{cases}}

smoke-fail-fast *cases: build
    uv run python3 scripts/run_circuits.py --fail-fast {{cases}}

smoke-ascii *cases: build
    uv run python3 scripts/run_circuits.py --output-format ascii {{cases}}

smoke-ascii-fail-fast *cases: build
    uv run python3 scripts/run_circuits.py --output-format ascii --fail-fast {{cases}}

export-compiled *cases: build
    uv run python3 scripts/run_circuits.py --compiled-dir .compiled {{cases}}

export-compiled-fail-fast *cases: build
    uv run python3 scripts/run_circuits.py --compiled-dir .compiled --fail-fast {{cases}}