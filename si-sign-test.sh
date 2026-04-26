#!/usr/bin/env bash
# Attempt to sign a throwaway string with the YubiKey, to confirm signing works
# before a real build. Tries the host GPG env first; if that can't sign, falls
# back to an isolated temp GNUPGHOME (see lib/gpg-env.sh). On failure it prints
# the manual setup steps and exits non-zero.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/yubikey-select.sh
source "$ROOT_DIR/lib/yubikey-select.sh"
# shellcheck source=lib/gpg-env.sh
source "$ROOT_DIR/lib/gpg-env.sh"

trap gpg_env_cleanup EXIT

pick_yubikey
echo "==> YubiKey: $YUBIKEY_DESC  [serial: $YUBIKEY_SERIAL]"
echo
echo "  NOTE: this signs a temporary string; your YubiKey PIN and a"
echo "        physical touch will be required."
echo

if ! gpg_env_prepare 1; then
  exit 1
fi

echo
echo "==> Sign test passed."
echo "    env:         $GPG_ENV_MODE"
echo "    signing key: $GPG_ENV_KEY"
if [[ "$GPG_ENV_MODE" == "temp" ]]; then
  echo "    (host GPG env could not sign; used an isolated temp environment)"
fi
