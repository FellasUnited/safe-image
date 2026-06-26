# Network modes

This image has two explicit modes managed by `safe-netmode`.

## Offline mode

```bash
safe-netmode offline
```

Expected behavior:

- NetworkManager is stopped.
- Radios are blocked.
- Non-loopback interfaces are set down.
- Main IPv4/IPv6 routes are flushed.
- nftables blocks input, forward, and output except loopback.

## Online mode

```bash
safe-netmode online
```

Expected behavior:

- nftables allows outbound traffic.
- Inbound traffic remains default-drop except loopback and established/related traffic.
- Radios are unblocked.
- Interfaces are brought up.
- NetworkManager is started.

Use online mode only when you intentionally need connectivity.

## Status

```bash
safe-status
safe-netmode status
```

## Connecting to Wi-Fi

The image ships NetworkManager with `wpa_supplicant` as its Wi-Fi backend
(the default). Go online first; then use `nmcli` or `nmtui`.

```bash
safe-netmode online                              # unblocks radios, starts NM
nmcli device wifi list                           # scan
nmcli device wifi connect <SSID> password <PSK>  # join
```

Interactive equivalent (curses UI):

```bash
nmtui
```

A connection saved by `nmcli` lives in `/etc/NetworkManager/system-connections/`
and is wiped at reboot — by design for a live image. Re-enter the credentials
after each boot, or copy a `.nmconnection` file from a USB stick before
running `safe-netmode online`.

If `nmcli device wifi list` shows no devices:

```bash
ip link                          # is the wlan interface present?
rfkill list                      # is it soft- or hard-blocked?
journalctl -u NetworkManager     # check NM logs
journalctl -u wpa_supplicant     # check supplicant logs
lspci -k | grep -A3 -i network   # confirm the driver is loaded
```

Some Wi-Fi chipsets need vendor firmware that is not bundled in the image.
`dmesg | grep -i firmware` will show the missing file, e.g.
`iwlwifi-...ucode`. The fix is to add `hardware.enableRedistributableFirmware
= true;` to `modules/base.nix` and rebuild — this is already enabled via
`installation-cd-minimal.nix`, so missing firmware usually means a fully
non-free driver (e.g. some Broadcom parts) that the live ISO does not carry.
