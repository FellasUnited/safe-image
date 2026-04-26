# YubiKey Setup

Move GPG subkeys onto a YubiKey and configure it for use.

> **Environment: safe-image (air-gapped)**
>
> Moving keys to the YubiKey (`keytocard`) is destructive -- the local
> private key is replaced with a stub pointing to the card.  This must
> be done on the safe-image where your backup is already
> confirmed.

## Prerequisites

- Keys generated per [01-generate-keys.md](01-generate-keys.md)
- Full keyring backed up to **two** encrypted USB sticks
- YubiKey 5 series (firmware 5.2.3+ for Ed25519)

> **STOP -- Verify you are offline.**
>
> ```bash
> ip link | grep 'state UP'
> ```
>
> No interfaces should be UP.

> **STOP -- Verify your backup exists before proceeding.**
>
> If you skip the backup and `keytocard` succeeds, the only copy of
> your subkey private material will be on the YubiKey.  If the card
> breaks, you lose those keys permanently.

## 1. Change YubiKey PINs

The default PINs are well-known and must be changed immediately.

> **Insert your YubiKey now.**

```bash
gpg --card-edit
```

```
gpg/card> admin
gpg/card> passwd
```

Change all three:

| PIN | Default | Min length | Purpose |
|-----|---------|------------|---------|
| User PIN | `123456` | 6 chars | Required for each sign/decrypt/auth operation |
| Admin PIN | `12345678` | 8 chars | Required for key management and card admin |
| Reset code | (none) | 8 chars | Unlocks the User PIN if blocked (3 wrong attempts) |

Choose strong, distinct values.  Write them down and store with your
backup USBs -- if you lose both PINs the card must be factory-reset.

```
gpg/card> quit
```

## 2. Set card metadata (optional)

```bash
gpg --card-edit
```

```
gpg/card> admin
gpg/card> name
  (enter surname, given name)
gpg/card> lang
  en
gpg/card> login
  your@email.com
gpg/card> quit
```

## 3. Move subkeys to YubiKey

```bash
gpg --edit-key "${KEYID}"
```

### Move the signing subkey

```
gpg> key 1
```

The first subkey (marked `[S]`) is now selected (shown with `*`).

```
gpg> keytocard
```

Select **1 - Signature key**.  Enter the Admin PIN when prompted.

```
gpg> key 1
```

Deselect it.

### Move the encryption subkey

```
gpg> key 2
```

Select the `[E]` subkey.

```
gpg> keytocard
```

Select **2 - Encryption key**.

```
gpg> key 2
```

### Move the authentication subkey

```
gpg> key 3
```

Select the `[A]` subkey.

```
gpg> keytocard
```

Select **3 - Authentication key**.

```
gpg> save
```

## 4. Verify

```bash
gpg --card-status
```

All three key slots should show fingerprints:

```
Signature key ....: <fingerprint>
Encryption key....: <fingerprint>
Authentication key: <fingerprint>
```

```bash
gpg --list-secret-keys --keyid-format long "${KEYID}"
```

Subkeys should show `ssb>` (the `>` means the key is on the card):

```
sec   ed25519/XXXXXXXXXXXXXXXX  ...  [C]
ssb>  ed25519/YYYYYYYYYYYYYYYY  ...  [S]
ssb>  cv25519/ZZZZZZZZZZZZZZZZ  ...  [E]
ssb>  ed25519/WWWWWWWWWWWWWWWW  ...  [A]
```

## 5. Export your public key for daily use

Save the public key so you can carry it to other machines:

```bash
gpg --armor --export "${KEYID}" > "${KEYID}-public.key"
```

> **Insert a regular (unencrypted) USB stick now** -- this is just for
> the public key, which is safe to share.

```bash
cp "${KEYID}-public.key" /run/media/$USER/<usb>/
sync
```

> **Remove the USB stick.**

## 6. Clean up the safe-image

After `keytocard`, the safe-image keyring contains material that
must be removed before you finish:

| What | Where | Status |
|------|-------|--------|
| Master private key | `~/.gnupg/` | Full copy -- **must be removed** |
| Subkey private keys | `~/.gnupg/` | Replaced by **stubs** (pointers to the YubiKey) |
| Public key | `~/.gnupg/` | Safe to keep, but not needed here |
| Exported `.key` / `.asc` files | `$HOME` | **Must be shredded** |

### What are stubs?

When you run `keytocard`, GnuPG moves the private key material onto
the YubiKey and replaces the local copy with a tiny **stub** file.
The stub records the card serial number and key slot so that when you
run `gpg --sign` on any machine, GnuPG knows to ask the YubiKey for
the operation instead of looking for a local private key.

You can see stubs in action -- `ssb>` (the `>`) means "key is on a
smartcard":

```
sec#  ed25519/XXXXXXXXXXXXXXXX  ...  [C]       <-- # = master absent
ssb>  ed25519/YYYYYYYYYYYYYYYY  ...  [S]       <-- > = on card (stub)
ssb>  cv25519/ZZZZZZZZZZZZZZZZ  ...  [E]       <-- > = on card (stub)
ssb>  ed25519/WWWWWWWWWWWWWWWW  ...  [A]       <-- > = on card (stub)
```

Stubs are not secret -- they contain no private key material.  They
only tell GnuPG "ask the YubiKey in slot X".

### Remove the master key

The master key should only exist in your offline backups.  Delete it
from this session's keyring:

```bash
gpg --delete-secret-keys "${KEYID}"
```

When prompted, confirm deleting **only the master key** (the card
stubs for subkeys remain).  Verify:

```bash
gpg --list-secret-keys "${KEYID}"
```

You should see `sec#` (the `#` means the master private key is absent)
and `ssb>` for each subkey.

### Shred exported key files

The `.key` and `.asc` files exported during
[01-generate-keys.md](01-generate-keys.md) are still in `$HOME` if
you are continuing in the same session (recommended).  These contain
raw private key material and must be destroyed:

```bash
shred -u "${KEYID}"-{master,subkeys,public}.key "${KEYID}-revoke.asc"
```

> `shred -u` overwrites the file contents with random data and then
> deletes it.  On SSDs the overwrite may not reach every cell, but it
> is still better than a plain `rm`.

Verify nothing remains:

```bash
ls "${KEYID}"*
# should show: No such file or directory
```

### Wipe the GnuPG directory (optional, recommended)

If you have no other keys on this safe-image session, you can
wipe the entire GnuPG state:

```bash
rm -rf ~/.gnupg
```

This is a live image -- the directory will not survive a reboot anyway.
But wiping it now prevents accidental exposure if you keep the session
running.

### Summary: what lives where after cleanup

| Location | Contains | Secret? |
|----------|----------|---------|
| YubiKey | Subkey private keys (S, E, A) | Yes -- protected by User PIN |
| Backup USB A | `master.key`, `subkeys.key`, `public.key`, `revoke.asc` | Yes -- protected by LUKS |
| Backup USB B | Same as USB A (duplicate) | Yes -- protected by LUKS |
| Public-key USB | `public.key` only | No -- safe to share |
| safe-image | Nothing (wiped) | -- |

## Next steps

> **You can now shut down the safe-image.**
>
> The YubiKey holds your subkeys.  The master key exists only in your
> encrypted backup USBs.  You will not need the safe-image again
> until you need to extend expiry, revoke, or recover.

- [03-daily-use.md](03-daily-use.md) -- set up your daily machine and
  start using the YubiKey (done on your regular workstation/laptop)
