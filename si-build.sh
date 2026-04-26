#!/usr/bin/env bash
set -euo pipefail

ENGINE="${ENGINE:-}"
IMAGE_NAME="${IMAGE_NAME:-safe-live-nixos-builder}"
CACHE_VOLUME="${CACHE_VOLUME:-safe-live-nix-store}"
USE_CACHE_VOLUME="${USE_CACHE_VOLUME:-1}"
SKIP_SIGN="${SKIP_SIGN:-0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$ROOT_DIR/out"

# shellcheck source=lib/yubikey-select.sh
source "$ROOT_DIR/lib/yubikey-select.sh"
# shellcheck source=lib/gpg-env.sh
source "$ROOT_DIR/lib/gpg-env.sh"

# Build artifacts land here first. Only moved to OUT_DIR when both build
# and signing succeed, so OUT_DIR is never left in a partial state.
WORK_DIR=$(mktemp -d /tmp/safe-live-build-XXXXXX)

cleanup() {
  gpg_env_cleanup
  rm -rf "$WORK_DIR"
}
trap 'echo; echo "==> Build interrupted."; cleanup; exit 130' INT TERM
trap cleanup EXIT

if [[ -z "$ENGINE" ]]; then
  if command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
  elif command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
  else
    echo "ERROR: podman or docker is required." >&2
    exit 1
  fi
fi

case "$ENGINE" in
  podman|docker) ;;
  *)
    echo "ERROR: ENGINE must be podman or docker, got: $ENGINE" >&2
    exit 1
    ;;
esac

# Podman on SELinux hosts needs label=disable because nixos/nix relocates memory.
SELINUX_ARGS=()
SRC_MOUNT="$ROOT_DIR:/src:ro"
WORK_MOUNT="$WORK_DIR:/out"
# The builder image is built locally and tagged localhost/...; it must never be
# pulled. Only podman accepts --pull=never on `run`; docker's default behavior
# already skips pulls when the image is present locally.
RUN_PULL_ARGS=()
if [[ "$ENGINE" == "podman" ]]; then
  SELINUX_ARGS=( --security-opt label=disable )
  RUN_PULL_ARGS=( --pull=never )
fi

echo "==> Building builder image with $ENGINE"
"$ENGINE" build "${SELINUX_ARGS[@]}" -f "$ROOT_DIR/Dockerfile.builder" -t "localhost/$IMAGE_NAME" "$ROOT_DIR"

CACHE_ARGS=()
if [[ "$USE_CACHE_VOLUME" == "1" ]]; then
  # Named volumes (no leading /) are auto-seeded by Podman/Docker from the
  # image's /nix on first use.  Bind-mount paths are not — an empty directory
  # mounted over /nix hides the shell the container needs to start the build.
  if [[ "$CACHE_VOLUME" == /* ]]; then
    mkdir -p "$CACHE_VOLUME"
    if [[ ! -d "$CACHE_VOLUME/store" ]]; then
      echo "==> Seeding nix store into $CACHE_VOLUME (first-time setup)..."
      "$ENGINE" run --rm --pull=never --net=none "${SELINUX_ARGS[@]}" \
        -v "$CACHE_VOLUME:/nix-seed" "localhost/$IMAGE_NAME" \
        sh -lc 'cp -rp /nix/. /nix-seed/'
    fi
  fi
  CACHE_ARGS=( -v "$CACHE_VOLUME:/nix" )
fi

if [[ "$SKIP_SIGN" != "1" ]]; then
  # Select (and export) the YubiKey once; YUBIKEY_SERIAL is inherited by
  # both si-sign-outputs.sh calls so the user is never prompted twice.
  pick_yubikey
  echo "==> YubiKey: $YUBIKEY_DESC  [serial: $YUBIKEY_SERIAL]"
  echo
  export YUBIKEY_SERIAL_PRINTED=1  # suppress duplicate print in si-sign-outputs.sh

  echo "==> Pre-flight: verifying YubiKey signing before build..."
  echo "    A temporary file is signed now (PIN + touch) so a build never"
  echo "    runs only to fail at signing."
  if [[ -t 0 ]]; then
    read -rp "  Press Enter when ready... " _
    echo
  fi
  # Prepare the signing env once (host as-is, else isolated temp). The exported
  # GPG_ENV_* / GNUPGHOME are inherited by the signing step below, so the user
  # selects the key and proves signing exactly once.
  if ! gpg_env_prepare 1; then
    exit 1
  fi
  echo "==> Signing key: $GPG_ENV_KEY  (env: $GPG_ENV_MODE)"
  echo "==> Pre-flight passed."
  echo
fi

echo "==> Building ISO"
"$ENGINE" run --rm \
  "${RUN_PULL_ARGS[@]}" \
  "${SELINUX_ARGS[@]}" \
  --network=host \
  -v "$SRC_MOUNT" \
  -v "$WORK_MOUNT" \
  "${CACHE_ARGS[@]}" \
  -w /src \
  "localhost/$IMAGE_NAME" \
  sh -lc '
    set -euo pipefail

    export NIX_REMOTE=local

    nix build \
      .#nixosConfigurations.safe-live.config.system.build.isoImage \
      --out-link /tmp/safe-live-result \
      --no-warn-dirty \
      --option filter-syscalls false \
      --option sandbox false

    cp -L /tmp/safe-live-result/iso/*.iso /out/
    cd /out
    sha256sum *.iso > SHA256SUMS
  '

echo
echo "==> Build complete (unsigned):"
ls -lh "$WORK_DIR"

if [[ "$SKIP_SIGN" != "1" ]]; then
  echo
  echo "==> Signing outputs (set SKIP_SIGN=1 to skip)"
  OUT_DIR="$WORK_DIR" "$ROOT_DIR/si-sign-outputs.sh" --no-smoke
fi

# Both build and signing succeeded — atomically promote to out/.
echo
echo "==> Promoting to out/..."
rm -rf "$OUT_DIR"
mv "$WORK_DIR" "$OUT_DIR"
trap - EXIT  # WORK_DIR is now OUT_DIR; don't delete it on exit

echo
echo "Done:"
ls -lh "$OUT_DIR"
