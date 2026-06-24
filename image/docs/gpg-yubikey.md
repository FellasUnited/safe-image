# GPG and YubiKey

## Installed tooling

- `gpg`, `gpg-agent`, `pinentry-curses`
- `opensc`
- `ykman` (yubikey-manager)
- `yubico-piv-tool`

pcscd runs and is the single owner of the reader. scdaemon is configured
with `disable-ccid` (see `/etc/gnupg/scdaemon.conf`), so it goes through
PC/SC instead of fighting pcscd for direct libusb access. All tools —
`gpg`, `ykman`, `opensc-tool`, `yubico-piv-tool` — share that one view
of the card and stay in sync.

If `gpg --card-status` ever returns "card not available", another PC/SC
client may be holding the reader exclusively. Close it and retry, or
`gpgconf --kill gpg-agent scdaemon` to reset.

## Useful checks

```bash
ykman list
ykman openpgp info
gpg --card-status
```

## KDF (PIN hashing)

KDF (Key Derived Function) makes `gpg` hash the PIN on the host before
sending it to the card, so the PIN is never transmitted over PC/SC or stored
on the card in clear text. It is enabled per card with
`gpg --card-edit > admin > kdf-setup` and shows up in `gpg --card-status` as
`KDF setting ......: on`.

It **must be turned on while the card is empty** — once subkeys are loaded
(`keytocard`) the setting is locked and changing it returns
`Conditions of use not satisfied`, recoverable only by a full
`ykman openpgp reset`. Provisioning enables it as the first step; see
[guides/02-yubikey-setup.md](guides/02-yubikey-setup.md#1-enable-kdf-then-change-the-yubikey-pins).

## Bootstrap the keyring on a fresh boot

The live image's home is tmpfs, so the GPG keyring starts empty every
boot. Re-import the public key:

```bash
sudo safe-netmode online           # the fetch needs network
safe-yubikey-fetch-pubkey        # one-shot wrapper around gpg card fetch
```

`safe-yubikey-fetch-pubkey` runs `gpg --card-edit > fetch` which tries two
attempts in order:

1. **Card URL** — `gpg --card-edit > admin > url` lets you save a URL on
   the card. Used if set.
2. **Keyserver lookup by fingerprint** — used when no URL is set. Pulls
   from whichever keyserver is configured in `/etc/gnupg/dirmngr.conf`.
   This image ships `hkp://keyserver.ubuntu.com:80`.

So even with no URL on the card, the fetch succeeds if your key was
uploaded to that keyserver. The same helper runs automatically inside
the host-side `make sign` / `make build` / `make verify` flows.

## Common operations

```bash
# Import your public key manually (from a file)
gpg --import pubkey.asc

# Trust it
gpg --edit-key <fingerprint>   # then: trust → 5 → quit

# Sign a file
gpg --local-user <fingerprint> --detach-sign --armor file.txt

# Encrypt a file
gpg --encrypt --recipient <fingerprint> file.txt

# SSH via GPG agent
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
ssh-add -l   # should list the YubiKey auth subkey
```

## If gpg --card-status fails

```bash
# Kill the agent and scdaemon so they re-initialise
gpgconf --kill gpg-agent scdaemon
gpg --card-status
```
