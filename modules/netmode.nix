{ pkgs, lib, ... }:

let
  lockdownRules = ''
    table inet si_net_lockdown {
      chain input {
        type filter hook input priority 0; policy drop;
        iif lo accept
        ct state established,related accept
      }

      chain forward {
        type filter hook forward priority 0; policy drop;
      }

      chain output {
        type filter hook output priority 0; policy drop;
        oif lo accept
      }
    }
  '';

  onlineRules = ''
    table inet si_net_online {
      chain input {
        type filter hook input priority 0; policy drop;
        iif lo accept
        ct state established,related accept
      }

      chain forward {
        type filter hook forward priority 0; policy drop;
      }

      chain output {
        type filter hook output priority 0; policy accept;
      }
    }
  '';

  siNetmode = pkgs.writeShellApplication {
    name = "si-netmode";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      gnused
      iproute2
      networkmanager
      nftables
      util-linux
      systemd
    ];
    text = ''
      set -euo pipefail

      MODE="''${1:-}"
      STATE_DIR="/run/si-netmode"
      STATE_FILE="$STATE_DIR/state"

      list_ifaces() {
        ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -v '^lo$' || true
      }

      write_state() {
        mkdir -p "$STATE_DIR"
        printf '%s\n' "$1" > "$STATE_FILE"
      }

      apply_offline_firewall() {
        nft delete table inet si_net_online 2>/dev/null || true
        nft delete table inet si_net_lockdown 2>/dev/null || true
        nft -f - <<'NFT'
${lockdownRules}
NFT
      }

      apply_online_firewall() {
        nft delete table inet si_net_lockdown 2>/dev/null || true
        nft delete table inet si_net_online 2>/dev/null || true
        nft -f - <<'NFT'
${onlineRules}
NFT
      }

      go_offline() {
        echo "[si-netmode] Going OFFLINE"

        apply_offline_firewall

        if systemctl is-active --quiet NetworkManager.service; then
          nmcli networking off || true
        fi

        systemctl stop NetworkManager.service || true
        systemctl stop NetworkManager-wait-online.service || true

        rfkill block all || true

        list_ifaces | while IFS= read -r iface; do
          [ -n "$iface" ] || continue
          ip link set "$iface" down || true
        done

        ip route flush table main || true
        ip -6 route flush table main || true

        write_state offline
      }

      go_online() {
        echo "[si-netmode] Going ONLINE"

        apply_online_firewall

        rfkill unblock all || true

        list_ifaces | while IFS= read -r iface; do
          [ -n "$iface" ] || continue
          ip link set "$iface" up || true
        done

        systemctl start NetworkManager.service || true
        nmcli networking on || true

        write_state online
      }

      case "$MODE" in
        offline)
          go_offline
          ;;
        online)
          go_online
          ;;
        status)
          echo "State: $(cat "$STATE_FILE" 2>/dev/null || echo unknown)"
          echo
          echo "== links =="
          ip -brief link || true
          echo
          echo "== addresses =="
          ip -brief addr || true
          echo
          echo "== rfkill =="
          rfkill list || true
          echo
          echo "== nftables =="
          nft list ruleset || true
          ;;
        *)
          echo "Usage: si-netmode {offline|online|status}" >&2
          exit 1
          ;;
      esac
    '';
  };

  safeStatus = pkgs.writeShellApplication {
    name = "safe-status";
    runtimeInputs = with pkgs; [
      coreutils
      gnupg
      iproute2
      networkmanager
      nftables
      pcsc-tools
      procps
      util-linux
      systemd
      yubikey-manager
    ];
    text = ''
      set -euo pipefail

      echo "== safe live status =="
      echo "hostname: $(hostname)"
      echo "netmode: $(cat /run/si-netmode/state 2>/dev/null || echo unknown)"

      echo
      echo "== network services =="
      systemctl --no-pager --plain status NetworkManager.service 2>/dev/null | sed -n '1,8p' || true

      echo
      echo "== links =="
      ip -brief link || true

      echo
      echo "== addresses =="
      ip -brief addr || true

      echo
      echo "== routes =="
      ip route || true
      ip -6 route || true

      echo
      echo "== rfkill =="
      rfkill list || true

      echo
      echo "== nftables =="
      sudo nft list ruleset 2>/dev/null || nft list ruleset 2>/dev/null || true

      echo
      echo "== yubikeys =="
      ykman list || true

      echo
      echo "== gpg card =="
      gpg --card-status || true
    '';
  };

  # Sends a desktop notification only when a graphical session is available.
  # Skips silently when run from a root shell or non-Wayland context.
  _notify = title: body: icon: urgency: ''
    if [ -n "''${WAYLAND_DISPLAY:-}''${DISPLAY:-}" ]; then
      notify-send -i ${icon} -u ${urgency} "${title}" "${body}" 2>/dev/null || true
    fi
  '';

  safeNetworkOff = pkgs.writeShellApplication {
    name = "safe-network-off";
    runtimeInputs = with pkgs; [ siNetmode libnotify ];
    text = ''
      if sudo -n /run/current-system/sw/bin/si-netmode offline; then
        ${_notify "Offline" "All interfaces disabled" "network-offline" "normal"}
      else
        ${_notify "Netmode failed" "Could not go offline" "dialog-error" "critical"}
      fi
    '';
  };

  safeNetworkOn = pkgs.writeShellApplication {
    name = "safe-network-on";
    runtimeInputs = with pkgs; [ siNetmode libnotify ];
    text = ''
      if sudo -n /run/current-system/sw/bin/si-netmode online; then
        ${_notify "Online" "Network enabled" "network-idle" "normal"}
      else
        ${_notify "Netmode failed" "Could not go online" "dialog-error" "critical"}
      fi
    '';
  };

  offlineDesktop = pkgs.makeDesktopItem {
    name = "si-netmode-offline";
    desktopName = "Go Offline (Disable Network)";
    genericName = "Safe Live Offline Mode";
    comment = "Disable all network interfaces and block traffic";
    exec = "/run/current-system/sw/bin/safe-network-off";
    icon = "network-offline";
    terminal = false;
    categories = [ "System" "Security" ];
  };

  onlineDesktop = pkgs.makeDesktopItem {
    name = "si-netmode-online";
    desktopName = "Go Online (Enable Network)";
    genericName = "Safe Live Online Mode";
    comment = "Re-enable network interfaces and allow outbound traffic";
    exec = "/run/current-system/sw/bin/safe-network-on";
    icon = "network-idle";
    terminal = false;
    categories = [ "System" "Security" ];
  };

  polkitPolicy = pkgs.stdenvNoCC.mkDerivation {
    name = "si-netmode-polkit-policy";
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/polkit-1/actions
      cat > $out/share/polkit-1/actions/org.local.si-netmode.policy <<'POLICY'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="org.local.si-netmode">
    <description>Toggle network mode</description>
    <message>Authentication is required to change network mode</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/run/current-system/sw/bin/si-netmode</annotate>
    <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
  </action>
</policyconfig>
POLICY
    '';
  };

in
{
  # NetworkManager is usable for the explicit online mode, but not started at boot.
  # The image boots into the lockdown ruleset below.
  networking.networkmanager.enable = true;
  networking.useDHCP = lib.mkForce false;
  systemd.services.NetworkManager.wantedBy = lib.mkForce [ ];
  systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;

  networking.firewall.enable = false;
  networking.nftables.enable = true;
  networking.nftables.ruleset = lockdownRules;

  systemd.services.si-netmode-default-offline = {
    description = "Set network mode to offline at boot";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-pre.target" ];
    before = [ "network-pre.target" "NetworkManager.service" "multi-user.target" "graphical.target" ];
    after = [ "nftables.service" "basic.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${siNetmode}/bin/si-netmode offline";
      RemainAfterExit = true;
    };
  };

  environment.systemPackages = [
    siNetmode
    safeNetworkOff
    safeNetworkOn
    safeStatus
    offlineDesktop
    onlineDesktop
    polkitPolicy
    pkgs.polkit
    pkgs.libnotify
  ];
}
