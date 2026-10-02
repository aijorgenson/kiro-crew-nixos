{
  description = "Kiro Crew desktop for NixOS, wrapping the official Linux AppImage";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              # Kiro CLI is under the AWS Intellectual Property License.
              # Allow that one package so `nix build` / `nix run` work
              # without turning on allowUnfree for everything else.
              config.allowUnfreePredicate =
                pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "kiro-cli" ];
            }
          )
        );
    in
    {
      packages = forAll (pkgs: rec {
        kiro-cli = pkgs.callPackage ./kiro-cli.nix { };
        kirocrew-desktop = pkgs.callPackage ./package.nix { inherit kiro-cli; };
        default = kirocrew-desktop;
      });

      overlays.default = final: prev: {
        kiro-cli = final.callPackage ./kiro-cli.nix { };
        kirocrew-desktop = final.callPackage ./package.nix { };
      };

      nixosModules.default =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [ self.overlays.default ];
          environment.systemPackages = [ pkgs.kirocrew-desktop ];
        };
    };
}
