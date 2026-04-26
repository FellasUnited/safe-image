{ pkgs, ... }:

{
  # Tooling so the live image can rebuild safe-image (or any Nix-based
  # ISO) from inside itself — making the project self-hosting.
  #
  # Podman is preferred over Docker on NixOS: rootless by default, no
  # daemon, no extra service unit, native cgroups v2. `dockerCompat`
  # adds a `docker` symlink so si-build.sh's ENGINE detection picks it
  # up under either name without changes.

  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.systemPackages = with pkgs; [
    gnumake
    podman-compose
    skopeo
    fuse-overlayfs
    slirp4netns
  ];
}
