{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    haskell-flake.url = "github:srid/haskell-flake";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.haskell-flake.flakeModule
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        {
          haskellProjects.ghc865 = {
            defaults.packages = { }; # Disable scanning for local package
            devShell.enable = false; # Disable devShells
            basePackages = pkgs.haskell.packages.ghc865Binary.override {
              packageSetConfig = self: super: {
                mkDerivation =
                  drv:
                  super.mkDerivation (
                    drv
                    // {
                      doCheck = false;
                      doHaddock = false;
                      enableExecutableProfiling = false;
                      enableLibraryProfiling = false;
                      enableSharedExecutables = true;
                      enableSharedLibraries = true;
                    }
                  );
              };
            };
            packages = {
              easyrender.source = "0.1.1.4";
              fixedprec.source = "0.2.2.2";
              HaskellForMaths.source = "0.4.9";
              random.source = "1.1";
            };

          };
          # MHPartitioner Haskell project
          haskellProjects.default = {
            basePackages = config.haskellProjects.ghc865.outputs.finalPackages;
            devShell.enable = false;
            # Filter files
            projectRoot =
              with pkgs;
              builtins.toString (
                lib.fileset.toSource {
                  root = ./.;
                  fileset = lib.fileset.unions [
                    ./app
                    ./src
                    ./test
                    ./MHPartitioner.cabal
                    ./LICENSE
                  ];
                }
              );
          };
          packages.default = pkgs.lib.makeOverridable (
            { kahypar }:
            pkgs.stdenvNoCC.mkDerivation {
              name = "mhpartitioner";
              buildInputs = [ config.packages.MHPartitioner ];
              nativeBuildInputs = with pkgs; [ makeWrapper ];
              unpackPhase = "true";
              buildPhase = "true";
              orig = config.packages.MHPartitioner;
              installPhase = ''
                mkdir -p $out/libexec/mhpartitioner
                ln -s ${kahypar}/bin/KaHyPar $out/libexec/mhpartitioner/
                ln -s ${kahypar}/share/kahypar $out/libexec/mhpartitioner/
                cp ${./libexec/PaToH} $out/libexec/mhpartitioner/
                mkdir -p $out/bin
                makeWrapper $orig/bin/Examples $out/bin/mhpartitioner-examples
                makeWrapper $orig/bin/Main $out/bin/mhpartitioner --add-flags -d=$out/libexec/mhpartitioner/
              '';

            }
          ) { kahypar = "/homeless-shelter"; };
          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              haskell.compiler.ghc865Binary
              libz.dev
            ];
            nativeBuildInputs = with pkgs; [
              cabal-install
              hpack
              pkg-config
              nil
              nixfmt-rfc-style
            ];
          };
        };
      flake = {

        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.

      };
    };
}
