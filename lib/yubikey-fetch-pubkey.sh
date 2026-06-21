#!/usr/bin/env bash
# Fetch the OpenPGP public key from the URL stored on the inserted YubiKey.
#
# The OpenPGP smartcard applet keeps only the private key + fingerprint;
# the public half must live elsewhere. `gpg --card-edit > fetch` downloads
# it from the URL written to the card with `gpg --card-edit > admin > url`.
#
# Two ways to use this file:
#
#   1. Sourced as a library (host signing/verify scripts):
#        source lib/yubikey-fetch-pubkey.sh
#        yubikey_fetch_pubkey            # prints status, returns 0 on success
#        yubikey_fetch_pubkey "$KEYFP"   # also asserts a specific fingerprint
#
#   2. Run directly (in the live image, after going online):
#        safe-yubikey-fetch-pubkey
#        safe-yubikey-fetch-pubkey <fingerprint>

yubikey_fetch_pubkey() {
  local want_fp="${1:-}"

  if ! gpg --card-status >/dev/null 2>&1; then
    echo "ERROR: GPG cannot access the card. Is the YubiKey inserted?" >&2
    return 1
  fi

  # Resolve the signing-key fingerprint from the card when not given.
  local key
  if [[ -n "$want_fp" ]]; then
    key="$want_fp"
  else
    # `|| true` so a non-zero exit (e.g. card-status fails, or awk over a
    # missing file) does not silently kill the script under `set -e`/pipefail.
    key=$(gpg --card-status 2>/dev/null \
      | awk '/^Signature key/ { sub(/.*: /, ""); gsub(/ /, ""); print; exit }' \
      || true)
  fi
  if [[ -z "$key" || "$key" == "[none]" ]]; then
    echo "ERROR: No signing key fingerprint on the YubiKey." >&2
    return 1
  fi

  if gpg --list-keys "$key" >/dev/null 2>&1; then
    echo "==> Public key $key already in keyring."
    return 0
  fi

  # `gpg --card-edit > fetch` has two attempts built in:
  #   1. URL of public key on the card (gpg --card-edit > admin > url) — preferred.
  #   2. If the URL is not set: keyserver lookup by the card's key fingerprint,
  #      using whichever keyserver is configured in dirmngr.conf.
  # We run fetch unconditionally so the keyserver fallback always gets a chance.
  # `|| true` on each: a non-zero exit (card-status failure, or awk over a
  # missing dirmngr.conf) must not silently abort under `set -e`/pipefail.
  local card_url keyserver
  card_url=$(gpg --card-status 2>/dev/null \
    | awk -F': ' '/^URL of public key/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }' \
    || true)
  # First match wins: user override beats system default.
  keyserver=$(awk '/^[[:space:]]*keyserver[[:space:]]/ { print $2; exit }' \
    "${GNUPGHOME:-$HOME/.gnupg}/dirmngr.conf" /etc/gnupg/dirmngr.conf 2>/dev/null \
    || true)
  : "${keyserver:=<dirmngr default>}"

  if [[ -z "$card_url" || "$card_url" == "[not set]" ]]; then
    echo "==> Card URL not set; trying keyserver lookup by fingerprint."
    echo "    Fingerprint: $key"
    echo "    Keyserver:   $keyserver"
  else
    echo "==> Fetching public key — tries card URL first, then keyserver if needed."
    echo "    Card URL:  $card_url"
    echo "    Keyserver: $keyserver"
  fi

  printf 'fetch\nquit\n' | gpg --command-fd 0 --no-tty --card-edit >/dev/null 2>&1 || true
  if gpg --list-keys "$key" >/dev/null 2>&1; then
    echo "==> Public key $key imported."
    return 0
  fi

  echo "ERROR: Fetch failed for $key." >&2
  echo "       Tried: card URL ($card_url) and keyserver ($keyserver)." >&2
  echo "       Possible causes: no network, key not published, wrong URL." >&2
  echo "       Recovery options:" >&2
  echo "         1. Import from file:    gpg --import /path/to/pubkey.asc" >&2
  echo "         2. Set URL on card:     gpg --card-edit > admin > url" >&2
  echo "         3. Try another server:  gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys $key" >&2
  return 1
}

# Run as standalone command when executed (not sourced).
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  set -euo pipefail
  yubikey_fetch_pubkey "$@"
fi
