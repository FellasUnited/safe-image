{ pkgs, lib, ... }:

{
  # pcscd is enabled and scdaemon is configured (below) to route through
  # PC/SC instead of using its built-in libusb CCID driver. This keeps
  # GPG, ykman, opensc, and yubico-piv-tool sharing a single coherent
  # view of the card; running both stacks against the same reader caused
  # `gpg --card-status` to flake out on bare metal.
  services.pcscd.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  services.udev.packages = with pkgs; [
    yubikey-personalization
    libfido2
  ];

  # Grant the active console user direct USB access to any Yubico device,
  # including the HID/hidraw interface needed by ykman.
  # MODE="0666" ensures any user can reach the device without relying on
  # logind uaccess propagation, which is timing-sensitive in QEMU passthrough.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb",    ATTRS{idVendor}=="1050", TAG+="uaccess", TAG+="udev-acl", GROUP="plugdev", MODE="0666"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1050", TAG+="uaccess", TAG+="udev-acl", GROUP="plugdev", MODE="0666"
  '';

  environment.etc."gnupg/scdaemon.conf" = {
    mode = "0644";
    text = ''
      # Disable scdaemon's built-in CCID (libusb direct) driver so it
      # goes through pcscd / libpcsclite. When both stacks try to claim
      # the YubiKey at once, scdaemon's internal driver loses the race
      # and `gpg --card-status` fails with "card not available". Routing
      # everything through pcscd makes GPG and PC/SC tools (ykman,
      # opensc, yubico-piv-tool) share one consistent view of the card.
      disable-ccid
    '';
  };

  environment.etc."gnupg/dirmngr.conf" = {
    mode = "0644";
    text = ''
      keyserver hkp://keyserver.ubuntu.com:80
    '';
  };

  # Re-trigger udev for USB devices at boot so MODE="0666" is applied to
  # devices that QEMU passes through before udev has settled.
  systemd.services.udev-trigger-usb = {
    description = "Re-apply udev rules for USB devices";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/udevadm trigger --subsystem-match=usb --action=add";
      ExecStartPost = "${pkgs.systemd}/bin/udevadm settle";
    };
  };

  # Ship the host-side YubiKey pubkey-fetch helper inside the image as a
  # PATH-reachable command. Single source of truth: lib/yubikey-fetch-pubkey.sh
  # in the repo, used by si-sign-outputs.sh / si-verify.sh on the host and
  # by this command from a fresh-boot shell in the guest.
  environment.systemPackages = with pkgs; [
    gnupg
    pinentry-curses
    opensc
    yubikey-manager
    yubikey-personalization
    yubico-piv-tool
    spice-vdagent
    (writeShellApplication {
      name = "safe-yubikey-fetch-pubkey";
      runtimeInputs = [ gnupg gawk ];
      text = ''
        ${builtins.readFile ../lib/yubikey-fetch-pubkey.sh}
      '';
    })
  ];

  # Enables clipboard sharing with the QEMU host via virtio-serial vdagent.
  services.spice-vdagentd.enable = true;
}
