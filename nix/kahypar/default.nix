{
  stdenv,
  cmake,
  ninja,
  lib,
  fetchFromGitHub,
  boost,
  git,
  pkg-config,
  doxygen,
  python3Packages,
}:
stdenv.mkDerivation (self: rec {
  pname = "kahypar";
  version = "1.3.5";
  src = fetchFromGitHub {
    owner = "kahypar";
    repo = "kahypar";
    rev = "v${version}";
    hash = "sha256-twrP6rWpZ/mJfj7AV8iTqFsLH5iybLhkl6zKCjDe1zI=";
    fetchSubmodules = true;
  };
  nativeBuildInputs = [
    cmake
    git
    doxygen
  ];
  propagatedBuildInputs = [ boost ];
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DBUILD_TESTING=ON"
    "-DKAHYPAR_INPUT_VALIDATION=OFF"
  ];
  patches = [ ./kahypar-pkgconfig.patch ];
  checkPhase = ''
    echo "Building integration tests"
    echo $PWD
    make integration_tests -j $NIX_BUILD_CORES
  '';
  postInstall = ''
    echo "Installing binaries"
    make install.library
    mkdir -p $out/share/kahypar
    cp -r ../config $out/share/kahypar/
  '';
  passthru = rec {
    mkPyBinding =
      { pybind11 }:
      stdenv.mkDerivation {
        name = "kahypar_python";
        inherit version src;
        buildInputs = [ boost ];
        nativeBuildInputs = [
          pybind11
          cmake
          git
          doxygen
        ];
        cmakeFlags = [
          "-DKAHYPAR_PYTHON_INTERFACE=1"
          "-DCMAKE_BUILD_TYPE=RELEASE"
          "-DKAHYPAR_INPUT_VALIDATION=OFF"
        ];
        preBuild = ''
          cd python
        '';
        installPhase = ''
          ls
          for i in *.so
          do
            install -D -m755 *.so $out/lib/kahypar.cpython-311-x86_64-linux-gnu.so
          done
        '';
      };

    pyBinding = mkPyBinding { pybind11 = python3Packages.pybind11; };
    mkPythonPackage =
      pythonPackages:
      pythonPackages.buildPythonPackage rec {
        pname = "kahypar";
        inherit version src;
        patches = [ ./kahypar-python-disable-input-validation.patch ];
        nativeBuildInputs = [
          cmake
          git
          doxygen
          pythonPackages.setuptools
        ];
        buildInputs = [ boost ];
        dontUseCmakeConfigure = true;
      };
    pythonPackage = mkPythonPackage python3Packages;
  };
})
