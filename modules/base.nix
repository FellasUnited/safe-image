{ pkgs, lib, ... }:

{
  system.stateVersion = "25.11";

  # Send kernel + systemd output to serial so QEMU smoke-tests can read it.
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty1" ];

  services.getty.autologinUser = lib.mkDefault "nixos";

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "plugdev" ];
    initialPassword = "nixos";
    # installation-cd-minimal sets initialHashedPassword = ""; clear it to
    # avoid the "multiple password options" evaluation warning.
    initialHashedPassword = lib.mkForce null;
  };

  # Auto-start Sway on TTY1 login.
  # loginShellInit is more reliable than profile.d with getty autologin on NixOS.
  programs.bash.loginShellInit = ''
    if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
      exec sway
    fi
  '';


  security.sudo.wheelNeedsPassword = false;

  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    bashInteractive
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    less
    emacs
    librewolf
    nano
    vim
    tmux
    git
    jq
    ripgrep
    fd
    file
    tree
    pciutils
    usbutils
    iproute2
    nftables
    util-linux
    lsof
    psmisc
  ];

  documentation.nixos.enable = false;
  programs.command-not-found.enable = false;
}
