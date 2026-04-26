#!/usr/bin/env bash
# Verifies signatures on artifacts in out/ against the YubiKey's signing key.
# Uses the same env setup as signing (lib/gpg-env.sh): host GPG env first, with
# an isolated temp GNUPGHOME fallback. Verification needs no PIN or touch — only
# card access (to read the signing-key fingerprint) and the public key in the
# keyring (fetched from the card URL / keyserver if missing).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"

# shellcheck source=lib/yubikey-select.sh
source "$ROOT_DIR/lib/yubikey-select.sh"
# shellcheck source=lib/gpg-env.sh
source "$ROOT_DIR/lib/gpg-env.sh"

trap gpg_env_cleanup EXIT

if [[ ! -d "$OUT_DIR" ]]; then
  echo "ERROR: out/ directory not found. Run 'make build' first." >&2
  exit 1
fi

pick_yubikey
echo "==> YubiKey: $YUBIKEY_DESC  [serial: $YUBIKEY_SERIAL]"

# need_sign=0: establish card access + pubkey only, no smoke (no touch).
if ! gpg_env_prepare 0; then
  exit 1
fi
KEY="$GPG_ENV_KEY"
echo "==> Signing key: $KEY  (env: $GPG_ENV_MODE)"

shopt -s nullglob
sigs=( "$OUT_DIR"/*.asc )
if (( ${#sigs[@]} == 0 )); then
  echo "ERROR: No signature files (*.asc) found in $OUT_DIR." >&2
  exit 1
fi

fail=0
for asc in "${sigs[@]}"; do
  target="${asc%.asc}"
  if [[ ! -f "$target" ]]; then
    echo "MISSING: $(basename "$target") (signature exists but file does not)"
    fail=1
    continue
  fi
  # --status-fd lets us check the actual signing key fingerprint, not just
  # that *some* key in the keyring validated the signature.
  status=$(gpg --status-fd 1 --verify "$asc" "$target" 2>/dev/null || true)
  if grep -q "^\[GNUPG:\] GOODSIG" <<<"$status" \
     && grep -q "^\[GNUPG:\] VALIDSIG [[:xdigit:]]*${KEY}" <<<"$status"; then
    echo "OK:      $(basename "$target")"
  else
    echo "BAD:     $(basename "$target")"
    fail=1
  fi
done

exit "$fail"
