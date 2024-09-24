# nix-shell -p cabal-install haskell.compiler.ghc865Binary hpack libz.dev pkg-config
{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    haskell-flake.url = "github:srid/haskell-flake";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # To import a flake module
        # 1. Add foo to inputs
        # 2. Add foo as a parameter to the outputs function
        # 3. Add here: foo.flakeModule
        inputs.haskell-flake.flakeModule
      ];
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        haskellProjects.ghc865 = {
          defaults.packages = {};  # Disable scanning for local package
          devShell.enable = false; # Disable devShells
          basePackages = pkgs.haskell.packages.ghc865Binary.override {
            packageSetConfig = self: super: {
              mkDerivation = drv: super.mkDerivation (drv // {
                doCheck = false;
                doHaddock = false;
                enableExecutableProfiling = false;
                enableLibraryProfiling = false;
                enableSharedExecutables = true;
                enableSharedLibraries = true;
              });
            };
          };
          packages = {
            easyrender.source = "0.1.1.4";
            fixedprec.source = "0.2.2.2";
            HaskellForMaths.source = "0.4.9";
            random.source = "1.1";
          };
          
        };
        haskellProjects.default = {
          basePackages = config.haskellProjects.ghc865.outputs.finalPackages;
        };
        #packages.default = pkgs.
      };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.

      };
    };
}
