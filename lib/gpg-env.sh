#!/usr/bin/env bash
# Prepare a working GPG environment for YubiKey signing/verification.
#
# Strategy: try the host's GPG env exactly as-is first; if it cannot reach the
# card / sign, fall back to a fully-configured isolated temp GNUPGHOME that
# takes over the reader and is torn down on cleanup.
#
# Why two paths:
#   - A correctly-configured host (scdaemon disable-ccid + pcsc, curses pinentry,
#     pubkey already in the keyring) signs with zero disruption — use it.
#   - A fresh/misconfigured host (e.g. a Fedora live OS) needs scdaemon routed
#     through pcscd, a terminal pinentry, and a pubkey fetched into an empty
#     keyring. We do all of that in a throwaway home so the host config and
#     keyring are never mutated.
#
# Only ONE scdaemon can hold the reader at a time (exclusive PC/SC). So the temp
# home cannot coexist with a running host scdaemon: the fallback kills the host
# scdaemon and restarts pcscd to take over the reader, then releases it on
# cleanup (the host scdaemon respawns on the host's next gpg use). This only
# happens when the host env already could not sign.
#
# Source this file, then:
#   gpg_env_prepare <need_sign>   # 1 = run an echo-sign smoke as the test
#                                 # 0 = card access + pubkey only (no touch)
# On success it exports: GPG_ENV_READY=1, GPG_ENV_MODE (host|temp),
# GPG_ENV_KEY (signing fingerprint), and GNUPGHOME (when temp). Register
# `trap gpg_env_cleanup EXIT` in the caller.

# Resolve sibling library (yubikey_fetch_pubkey) relative to this file.
_GPG_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/yubikey-fetch-pubkey.sh
source "$_GPG_ENV_DIR/yubikey-fetch-pubkey.sh"

# Keyserver used by the isolated temp home. keyserver.ubuntu.com is reachable
# over hkps/443 (survives networks that block hkp/11371) and serves the full key
# with its UIDs intact, which is what verification needs. It also matches the
# keyserver the live image ships in dirmngr.conf (modules/yubikey-gpg.nix).
GPG_ENV_TEMP_KEYSERVER="${GPG_ENV_TEMP_KEYSERVER:-hkps://keyserver.ubuntu.com}"

# Set by gpg_env_prepare; consumed by gpg_env_cleanup.
GPG_ENV_TEMP_HOME=""

_gpg_env_pcscd_running() {
  systemctl is-active --quiet pcscd.service 2>/dev/null \
    || systemctl is-active --quiet pcscd.socket 2>/dev/null
}

# Start pcscd if it is not already active. Does not restart a running daemon —
# the host attempt must not disturb a working setup.
_gpg_env_ensure_pcscd() {
  command -v pcscd >/dev/null 2>&1 || return 0
  _gpg_env_pcscd_running && return 0
  echo "==> pcscd is not running; starting it..." >&2
  sudo systemctl daemon-reload 2>/dev/null || true
  sudo systemctl start pcscd.socket 2>/dev/null \
    || sudo systemctl start pcscd.service 2>/dev/null || true
}

# Resolve the signing-key fingerprint from the inserted card.
_gpg_env_card_key() {
  gpg --card-status 2>/dev/null \
    | awk '/^Signature key/ { sub(/.*: /, ""); gsub(/ /, ""); print; exit }'
}

# Validate the CURRENT GNUPGHOME: card reachable, signing key known, pubkey in
# keyring (fetched if needed), and — when need_sign=1 — an echo string signs and
# verifies. Sets GPG_ENV_KEY on success. Quiet; returns 0/1.
_gpg_env_validate() {
  local need_sign="$1" key tmp

  gpg --card-status >/dev/null 2>&1 || return 1

  key=$(_gpg_env_card_key)
  [[ -n "$key" && "$key" != "[none]" ]] || return 1

  # Bring the public half into this keyring (no-op if already present).
  yubikey_fetch_pubkey "$key" >/dev/null 2>&1 || return 1

  if [[ "$need_sign" == "1" ]]; then
    tmp=$(mktemp)
    echo "safe-image sign-env test" > "$tmp"
    # Re-poke the card: pcscd/scdaemon can drop the connection between calls.
    gpg --card-status >/dev/null 2>&1 || true
    if ! gpg --yes --local-user "$key" --detach-sign --armor "$tmp" \
         || ! gpg --verify "$tmp.asc" "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp" "$tmp.asc"
      return 1
    fi
    rm -f "$tmp" "$tmp.asc"
  fi

  GPG_ENV_KEY="$key"
  return 0
}

# Build the isolated temp GNUPGHOME and take over the reader from the host.
_gpg_env_setup_temp() {
  local curses keyserver
  curses=$(command -v pinentry-curses 2>/dev/null || true)

  GPG_ENV_TEMP_HOME=$(mktemp -d /tmp/safe-live-gnupg-XXXXXX)
  chmod 700 "$GPG_ENV_TEMP_HOME"

  {
    echo "disable-ccid"   # route through pcscd instead of scdaemon's CCID driver
    echo "pcsc-shared"    # don't hold the reader exclusively
  } > "$GPG_ENV_TEMP_HOME/scdaemon.conf"

  if [[ -n "$curses" ]]; then
    echo "pinentry-program $curses" > "$GPG_ENV_TEMP_HOME/gpg-agent.conf"
  fi

  # Carry over a host keyserver if set, else use our reliable default.
  keyserver=$(awk '/^[[:space:]]*keyserver[[:space:]]/ { print $2; exit }' \
    "${HOME}/.gnupg/dirmngr.conf" /etc/gnupg/dirmngr.conf 2>/dev/null)
  : "${keyserver:=$GPG_ENV_TEMP_KEYSERVER}"
  echo "keyserver $keyserver" > "$GPG_ENV_TEMP_HOME/dirmngr.conf"

  # Release the reader from the host scdaemon, then take it over via pcscd.
  gpgconf --kill scdaemon >/dev/null 2>&1 || true
  if command -v pcscd >/dev/null 2>&1; then
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl restart pcscd.service 2>/dev/null \
      || sudo systemctl restart pcscd.socket 2>/dev/null || true
  fi

  export GNUPGHOME="$GPG_ENV_TEMP_HOME"
}

# Print manual recovery steps when neither env can sign.
gpg_env_print_help() {
  cat >&2 <<'EOF'

==> Could not establish a working GPG signing environment.

To make the YubiKey usable for signing, on the host:

  1. Install the signing stack (Fedora):
       sudo dnf install -y gnupg2 gnupg2-scdaemon pinentry-curses \
                           pcsc-lite pcsc-lite-ccid yubikey-manager

  2. Route scdaemon through pcscd (avoids the reader being held twice):
       printf 'disable-ccid\npcsc-shared\n' >> ~/.gnupg/scdaemon.conf
       sudo systemctl restart pcscd
       gpgconf --kill scdaemon

  3. Confirm the card is seen:
       gpg --card-status        # should list a "Signature key"

  4. Get the PUBLIC key into the keyring (the card holds only the private half):
       ./lib/yubikey-fetch-pubkey.sh                 # card URL, then keyserver
       gpg --import /path/to/your-pubkey.asc         # or from a file
       gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys <fingerprint>
     Tip: set a durable URL once so fetch always works:
       gpg --card-edit  ->  admin  ->  url <https-url-to-pubkey>

  5. Re-run:  make sign-test
EOF
}

# Prepare a signing env: host as-is first, isolated temp home as fallback.
# Idempotent — a no-op when a parent process already prepared one.
gpg_env_prepare() {
  local need_sign="${1:-0}"

  # Inherit a parent-prepared env (e.g. si-build.sh pre-flight -> signing step).
  if [[ "${GPG_ENV_READY:-0}" == "1" ]]; then
    return 0
  fi

  # curses pinentry needs the controlling terminal; only set when we have one.
  if [[ -t 0 ]]; then
    GPG_TTY=$(tty)
    export GPG_TTY
  fi

  _gpg_env_ensure_pcscd

  # Host attempt — never mutates host config. Skippable for testing the fallback.
  if [[ "${GPG_ENV_FORCE_TEMP:-0}" != "1" ]]; then
    if _gpg_env_validate "$need_sign"; then
      GPG_ENV_MODE="host"
      export GPG_ENV_READY=1 GPG_ENV_MODE GPG_ENV_KEY
      return 0
    fi
    echo "==> Host GPG env can't sign; falling back to an isolated temp env..." >&2
  fi

  # Temp fallback — isolated home, takes over the reader.
  _gpg_env_setup_temp
  if _gpg_env_validate "$need_sign"; then
    GPG_ENV_MODE="temp"
    export GPG_ENV_READY=1 GPG_ENV_MODE GPG_ENV_KEY GNUPGHOME
    return 0
  fi

  gpg_env_print_help
  return 1
}

# Tear down a temp env we created. No-op for host mode or for child processes
# that merely inherited a parent-owned temp home.
gpg_env_cleanup() {
  [[ -n "$GPG_ENV_TEMP_HOME" && -d "$GPG_ENV_TEMP_HOME" ]] || return 0
  gpgconf --homedir "$GPG_ENV_TEMP_HOME" --kill all >/dev/null 2>&1 || true
  rm -rf "$GPG_ENV_TEMP_HOME"
  GPG_ENV_TEMP_HOME=""
}
