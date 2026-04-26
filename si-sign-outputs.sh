#!/usr/bin/env bash
# Signs ISO and SHA256SUMS in out/ with the YubiKey GPG signing key.
# Requires: gpg, ykman, a YubiKey with a signing subkey inserted.
#
# The signing environment (host as-is, or an isolated temp GNUPGHOME fallback)
# is established by lib/gpg-env.sh. When invoked by si-build.sh the env is
# prepared once up front and inherited here via GPG_ENV_READY.
#
# Flags:
#   --smoke-only   Run the echo-sign env test only; do not sign any files.
#   --no-smoke     Skip the echo-sign test and go straight to signing.
set -euo pipefail

SMOKE_ONLY=0
NO_SMOKE=0
for arg in "$@"; do
  case "$arg" in
    --smoke-only) SMOKE_ONLY=1 ;;
    --no-smoke)   NO_SMOKE=1 ;;
    *) echo "ERROR: Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"

# shellcheck source=lib/yubikey-select.sh
source "$ROOT_DIR/lib/yubikey-select.sh"
# shellcheck source=lib/gpg-env.sh
source "$ROOT_DIR/lib/gpg-env.sh"

trap gpg_env_cleanup EXIT

if [[ "$SMOKE_ONLY" != "1" ]] && [[ ! -d "$OUT_DIR" ]]; then
  echo "ERROR: out/ directory not found. Run a build first." >&2
  exit 1
fi

pick_yubikey
# Only print when running standalone (si-build.sh prints it when calling us).
[[ -z "${YUBIKEY_SERIAL_PRINTED:-}" ]] && echo "==> YubiKey: $YUBIKEY_DESC  [serial: $YUBIKEY_SERIAL]"

# Whether gpg_env_prepare runs the echo-sign smoke (one PIN + touch). Skipped
# with --no-smoke, and a no-op anyway when a parent already prepared the env.
NEED_SIGN=1
[[ "$NO_SMOKE" == "1" ]] && NEED_SIGN=0

# Standalone heads-up before the smoke's PIN/touch (not when inheriting a
# parent-prepared env, which already did this).
if [[ "${GPG_ENV_READY:-0}" != "1" && "$NEED_SIGN" == "1" && -t 0 ]]; then
  echo
  echo "  NOTE: a temporary file will be signed to test the YubiKey."
  echo "        Your PIN and a physical touch will be required."
  read -rp "  Press Enter when ready... " _
  echo
fi

if ! gpg_env_prepare "$NEED_SIGN"; then
  exit 1
fi

KEY="$GPG_ENV_KEY"
echo "==> Signing key: $KEY  (env: $GPG_ENV_MODE)"

if [[ "$SMOKE_ONLY" == "1" ]]; then
  echo "==> Sign test passed."
  exit 0
fi

if [[ "$NEED_SIGN" == "1" && -t 0 ]]; then
  echo
  echo "  NOTE: each output file needs your YubiKey PIN and a physical touch."
  read -rp "  Press Enter when ready... " _
  echo
fi

echo "==> Signing outputs in out/"
# Re-establish the scdaemon -> card connection after any prompt pause.
gpg --card-status >/dev/null 2>&1 || true
for f in "$OUT_DIR"/*.iso "$OUT_DIR"/SHA256SUMS; do
  [[ -f "$f" ]] || continue
  rm -f "$f.asc"
  gpg --batch --yes --local-user "$KEY" --detach-sign --armor "$f"
  echo "    signed: $(basename "$f")"
done

echo
echo "Signatures:"
ls -lh "$OUT_DIR"/*.asc
