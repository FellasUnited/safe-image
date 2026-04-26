#!/usr/bin/env bash
# Boots the built ISO under QEMU.
# Default: headless smoke-test (checks serial for login prompt).
# GUI=1:   opens a display window for interactive testing; no pass/fail.
# Requires: qemu-system-x86_64
set -euo pipefail

GUI="${GUI:-0}"
SPICE="${SPICE:-0}"
TIMEOUT="${TIMEOUT:-600}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$ROOT_DIR/out"

# shellcheck source=lib/yubikey-select.sh
source "$ROOT_DIR/lib/yubikey-select.sh"

ISO=$(ls "$OUT_DIR"/safe-live-nixos-sway-*.iso 2>/dev/null | head -1)
if [[ -z "$ISO" ]]; then
  echo "ERROR: No ISO found in out/. Run 'make build' first." >&2
  exit 1
fi

echo "==> Testing: $(basename "$ISO")"

if [[ "$GUI" == "1" ]]; then
  echo "==> GUI mode: booting ISO in QEMU window (close window to stop)."
  echo "    TIP: Press Ctrl+Alt+G in the QEMU window to capture keyboard"
  echo "         input (required for Super/Win key bindings inside the guest)."

  YUBIKEY_ARGS=()
  if pick_yubikey; then
    echo "==> Passing through YubiKey: $YUBIKEY_DESC  [serial: $YUBIKEY_SERIAL]"
    USB_DEV="/dev/bus/usb/$(printf '%03d' "${YUBIKEY_BUS}")/$(printf '%03d' "${YUBIKEY_DEV}")"
    if [[ ! -r "$USB_DEV" || ! -w "$USB_DEV" ]]; then
      echo "==> No rw access to $USB_DEV — applying temporary fix with sudo..." >&2
      echo "    (Permanent fix: install yubikey-manager on the host)" >&2
      sudo chmod o+rw "$USB_DEV" 2>/dev/null \
        || { echo "WARNING: Could not fix USB permissions; YubiKey passthrough may fail." >&2; }
    fi
    # xHCI (USB 3.0 controller) handles YubiKeys better than the legacy -usb UHCI.
    YUBIKEY_ARGS=(
      -device "qemu-xhci,id=xhci"
      -device "usb-host,bus=xhci.0,hostbus=${YUBIKEY_BUS},hostaddr=${YUBIKEY_DEV}"
    )
  else
    echo "    No YubiKey detected — proceeding without passthrough."
  fi

  # Two clipboard paths:
  #   SPICE=1  -> use `-display spice-app` (auto-launches remote-viewer from
  #              virt-viewer) with the spice-vdagent channel. Reliable
  #              clipboard sync; needed on distros (like Fedora) whose QEMU
  #              is built without GTK clipboard support.
  #   default  -> `-display gtk` with QEMU's built-in qemu-vdagent chardev.
  #              Clipboard works only if QEMU was built with `clipboard=on`
  #              for GTK; detected at runtime.
  if [[ "$SPICE" == "1" ]]; then
    if ! command -v remote-viewer >/dev/null 2>&1; then
      echo "ERROR: SPICE=1 requires remote-viewer (virt-viewer package)." >&2
      echo "       Install on Fedora:  sudo dnf install virt-viewer" >&2
      exit 1
    fi
    echo "==> SPICE mode: launching via remote-viewer with vdagent clipboard."
    DISPLAY_ARGS=( -display spice-app,gl=off )
    # qxl is SPICE's native VGA; virtio-vga over spice-app renders garbled
    # (vertical stripes) without explicit GL config.
    VGA_ARGS=( -vga qxl )
    CLIPBOARD_ARGS=(
      -device virtio-serial-pci
      -chardev spicevmc,id=spicechannel0,name=vdagent
      -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0
    )
  else
    DISPLAY_OPTS="gtk,zoom-to-fit=off"
    if qemu-system-x86_64 -help 2>&1 | grep -q "clipboard=on"; then
      DISPLAY_OPTS="${DISPLAY_OPTS},clipboard=on"
    else
      echo "==> NOTE: This QEMU build was compiled without gtk clipboard support."
      echo "    Host<->guest clipboard sync will not work in gtk mode."
      echo "    For working clipboard, run:  SPICE=1 make test-gui"
    fi
    DISPLAY_ARGS=( -display "$DISPLAY_OPTS" )
    VGA_ARGS=( -device virtio-vga,xres=1920,yres=1080 )
    CLIPBOARD_ARGS=(
      -device virtio-serial-pci
      -chardev qemu-vdagent,id=vdagent,name=vdagent,clipboard=on
      -device virtserialport,chardev=vdagent,name=com.redhat.spice.0
    )
  fi

  exec qemu-system-x86_64 \
    -enable-kvm \
    -m 4096 \
    -smp 4 \
    -cdrom "$ISO" \
    -boot d \
    "${DISPLAY_ARGS[@]}" \
    "${VGA_ARGS[@]}" \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0 \
    "${CLIPBOARD_ARGS[@]}" \
    "${YUBIKEY_ARGS[@]}" \
    -no-reboot
fi

SERIAL_LOG=$(mktemp /tmp/safe-live-serial-XXXXXX.log)
trap 'kill "$QEMU_PID" 2>/dev/null; rm -f "$SERIAL_LOG"' EXIT

qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -smp 2 \
  -cdrom "$ISO" \
  -boot d \
  -display none \
  -monitor none \
  -serial "file:$SERIAL_LOG" \
  -no-reboot \
  &
QEMU_PID=$!

echo "==> Waiting up to ${TIMEOUT}s for boot and offline confirmation..."

deadline=$(( $(date +%s) + TIMEOUT ))
while (( $(date +%s) < deadline )); do
  # The login prompt or shell prompt reaching ttyS0 means multi-user.target
  # completed, which includes si-netmode-default-offline (boots offline).
  if grep -q "safe-live login:\|nixos@safe-live" "$SERIAL_LOG" 2>/dev/null; then
    echo "PASS: safe-live booted and reached login on ttyS0."
    exit 0
  fi
  sleep 2
done

echo "FAIL: offline mode not confirmed within ${TIMEOUT}s."
echo "--- Last 20 lines of serial log ---"
tail -20 "$SERIAL_LOG" || true
exit 1
