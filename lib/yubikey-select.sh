#!/usr/bin/env bash
# Shared YubiKey selection helper. Source this file; call pick_yubikey.
#
# After pick_yubikey returns 0:
#   YUBIKEY_SERIAL  — serial number
#   YUBIKEY_DESC    — human-readable description (model + firmware)
#   YUBIKEY_BUS     — USB bus number (decimal, for QEMU passthrough)
#   YUBIKEY_DEV     — USB device number (decimal, for QEMU passthrough)
#
# If YUBIKEY_SERIAL is already set in the environment, the matching key is
# used automatically (no prompt, no file written). This is the intended way
# for build-container.sh to pass the selection to si-sign-outputs.sh without
# persisting anything to disk.

# Prints lines of the form: "<serial> <bus> <dev> <desc>"
_yk_scan() {
  # Build serial→"bus dev" map from sysfs.
  # Tries: (1) sysfs serial file, (2) udevadm ID_SERIAL_SHORT.
  # YubiKey iSerial in sysfs matches ykman's decimal serial when present.
  declare -A _yk_busdev
  local d
  for d in /sys/bus/usb/devices/*/; do
    [[ -f "${d}idVendor" ]] || continue
    [[ "$(cat "${d}idVendor" 2>/dev/null)" == "1050" ]] || continue
    local b n s
    b=$(cat "${d}busnum" 2>/dev/null || true)
    n=$(cat "${d}devnum" 2>/dev/null || true)
    [[ -n "$b" && -n "$n" ]] || continue
    s=$(cat "${d}serial" 2>/dev/null || true)
    if [[ -z "$s" ]]; then
      s=$(udevadm info --query=property --path="${d%/}" 2>/dev/null \
          | awk -F= '/^ID_SERIAL_SHORT=/{print $2}' || true)
    fi
    [[ -n "$s" ]] || continue
    _yk_busdev["$s"]="$((10#$b)) $((10#$n))"
  done

  # Positional fallback: lsusb and ykman both enumerate Yubico devices in
  # bus/dev order via libusb, so index N in ykman matches index N in lsusb.
  local -a _lsusb_busdevs
  while IFS= read -r line; do
    local b d2
    b=$(echo "$line" | awk '{print $2}')
    d2=$(echo "$line" | awk '{print $4}' | tr -d ':')
    _lsusb_busdevs+=("$((10#$b)) $((10#$d2))")
  done < <(lsusb 2>/dev/null | grep -i " 1050:")

  local idx=0
  while IFS= read -r ykman_line; do
    # ykman: "YubiKey 5C NFC (5.7.4) [OTP+FIDO+CCID] Serial: 28850028"
    local serial desc
    serial=$(echo "$ykman_line" | grep -oP 'Serial: \K\d+')
    desc=$(echo "$ykman_line" | sed 's/ Serial:.*//')
    [[ -z "$serial" ]] && { (( idx++ )) || true; continue; }

    local busdev="${_yk_busdev[$serial]:-}"
    if [[ -z "$busdev" ]] && (( idx < ${#_lsusb_busdevs[@]} )); then
      busdev="${_lsusb_busdevs[$idx]}"
    fi

    if [[ -z "$busdev" ]]; then
      echo "WARNING: Could not find USB location for YubiKey serial $serial" >&2
      (( idx++ )) || true; continue
    fi

    printf '%s %s %s\n' "$serial" "$busdev" "$desc"
    (( idx++ )) || true
  done < <(ykman list 2>/dev/null)
}

pick_yubikey() {
  local entries=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && entries+=("$line")
  done < <(_yk_scan)

  if [[ ${#entries[@]} -eq 0 ]]; then
    echo "ERROR: No YubiKey detected." >&2
    return 1
  fi

  local chosen=""

  # If YUBIKEY_SERIAL is already set (passed from a parent script), find the
  # matching entry without prompting or writing anything.
  if [[ -n "${YUBIKEY_SERIAL:-}" ]]; then
    for entry in "${entries[@]}"; do
      local s
      s=$(echo "$entry" | awk '{print $1}')
      if [[ "$s" == "$YUBIKEY_SERIAL" ]]; then
        chosen="$entry"
        break
      fi
    done
    if [[ -z "$chosen" ]]; then
      echo "ERROR: Previously selected YubiKey (serial $YUBIKEY_SERIAL) is no longer connected." >&2
      return 1
    fi
  elif [[ ${#entries[@]} -eq 1 ]]; then
    chosen="${entries[0]}"
  else
    echo "Multiple YubiKeys detected:" >&2
    for i in "${!entries[@]}"; do
      local s d
      s=$(echo "${entries[$i]}" | awk '{print $1}')
      d=$(echo "${entries[$i]}" | cut -d' ' -f4-)
      printf "  %d) %s  [serial: %s]\n" "$((i+1))" "$d" "$s" >&2
    done
    local choice
    while true; do
      read -rp "Select YubiKey [1-${#entries[@]}]: " choice >&2
      [[ "$choice" =~ ^[0-9]+$ ]] \
        && (( choice >= 1 && choice <= ${#entries[@]} )) \
        && break
      echo "Invalid selection." >&2
    done
    chosen="${entries[$((choice-1))]}"
  fi

  YUBIKEY_SERIAL=$(echo "$chosen" | awk '{print $1}')
  YUBIKEY_BUS=$(echo "$chosen"    | awk '{print $2}')
  YUBIKEY_DEV=$(echo "$chosen"    | awk '{print $3}')
  YUBIKEY_DESC=$(echo "$chosen"   | cut -d' ' -f4-)

  export YUBIKEY_SERIAL YUBIKEY_BUS YUBIKEY_DEV YUBIKEY_DESC
  return 0
}
