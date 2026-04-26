{ modulesPath, lib, config, ... }:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"

    ./modules/base.nix
    ./modules/builder.nix
    ./modules/docs.nix
    ./modules/netmode.nix
    ./modules/sway.nix
    ./modules/yubikey-gpg.nix
  ];

  networking.hostName = "safe-live";

  image.baseName = lib.mkForce "safe-live-nixos-sway-${config.system.nixos.label}-x86_64-linux";
}
