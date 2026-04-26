{
  description = "Reproducible NixOS Sway live image with offline-first networking, firewall, GPG, and YubiKey tooling";

  inputs = {
    # Update intentionally and commit flake.lock when you want newer packages.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
  {
    nixosConfigurations.safe-live = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit self;
      };
      modules = [
        ./iso.nix
      ];
    };
  };
}
