# Guides

## Daily machine setup

See [host-setup.md](../host-setup.md) to configure pcscd, GPG, udev rules,
and touch notifications on a daily workstation after completing key setup here.

## YubiKey & GPG

Step-by-step workflows for managing GPG keys with a YubiKey.
These guides are installed into the live image at `/etc/safe-live/docs/guides/`.

### OpenPGP (guides 1-6)

These use the YubiKey's **OpenPGP applet** for GPG signing, encryption,
and SSH authentication.

| # | Guide | Environment | Description |
|---|-------|-------------|-------------|
| 1 | [Generate Keys](01-generate-keys.md) | safe-image | Create Ed25519 master key + subkeys |
| 2 | [YubiKey Setup](02-yubikey-setup.md) | safe-image | Move subkeys to YubiKey, change PINs, clean up |
| 3 | [Daily Use](03-daily-use.md) | Any machine | Sign, encrypt, Git, SSH with YubiKey |
| 4 | [Extend Expiry](04-extend-expiry.md) | safe-image | Renew subkeys before they expire |
| 5 | [Revoke Keys](05-revoke-keys.md) | safe-image | Revoke master key or individual subkeys |
| 6 | [Recovery](06-recovery.md) | safe-image | Backup, restore, factory reset, lost YubiKey |

### FIDO2 (guides 7-8)

These use the YubiKey's **FIDO2 applet** for system-level
authentication.  FIDO2 is a separate applet on the same physical key
-- it has its own PIN, independent from the OpenPGP User/Admin PINs.

| # | Guide | Environment | Description |
|---|-------|-------------|-------------|
| 7 | [Linux Login](07-linux-login.md) | Any machine | YubiKey FIDO2 for login, sudo, screen unlock |
| 8 | [LUKS Unlock](08-luks-unlock.md) | Any machine | YubiKey FIDO2 to unlock encrypted disk at boot |

## Environment rule

Any operation that touches **private key material** (master key,
`keytocard`, revocation) must be performed on the **safe-image
booted offline**.  The master key must never exist on a
network-connected machine.

Operations that only use the **YubiKey subkeys** (signing, encryption,
SSH) or **public keys** (verification, import, keyserver publish) can
be done on any machine.

Guides 7-8 (FIDO2) are always performed on a daily machine -- they
do not involve GPG private keys.

Each guide states its required environment at the top.  When a guide
switches environments mid-workflow (e.g. "export the public key on the
safe-image, then import it on your daily machine"), the change is
called out with a blockquote.

## Safety conventions used in these guides

The guides use consistent alert patterns:

| Alert | Meaning |
|-------|---------|
| **STOP -- Verify you are offline** | Run `ip link \| grep 'state UP'` before handling any private key material |
| **Insert your ... USB now** | Plug in the named USB stick at this point |
| **Remove the ... USB now** | Unplug it before proceeding to the next step |
| **You must publish to keyservers** | The change is not effective until others can fetch the updated key |

Backup USBs are always referred to as **PRIMARY** and **DUPLICATE**.
Both must be updated whenever the public key changes (expiry extension,
revocation, new subkeys).

## Keyserver publishing checklist

You **must** publish your public key to keyservers after:

- Initial key creation (in [03-daily-use.md](03-daily-use.md))
- Extending subkey expiry ([04-extend-expiry.md](04-extend-expiry.md))
- Revoking a subkey or the master key ([05-revoke-keys.md](05-revoke-keys.md))
- Restoring to a new YubiKey ([06-recovery.md](06-recovery.md))

```bash
gpg --keyserver hkps://keys.openpgp.org --send-keys "${KEYID}"
```

## Recommended reading order

**First-time setup:** 1 -> 2 -> 3

**Harden daily machine:** 7 (login/sudo) -> 8 (LUKS)

**Annual maintenance:** 4 (extend subkey expiry)

**Emergency:** 5 (revoke) -> 6 (recovery) -> 1 (new keys if needed)

## Algorithm choices

Guides 1-6 use **Ed25519** (signing/certify/authenticate) and
**Cv25519** (encryption).  These are the strongest elliptic curve
algorithms supported by YubiKey 5 series (firmware 5.2.3+) and modern
GnuPG (2.3+).  They offer better security and performance than RSA
at much shorter key lengths.

Guides 7-8 use **FIDO2/CTAP2** with the YubiKey's built-in
credential storage.  No algorithm choice is needed -- the protocol
handles key generation internally.
