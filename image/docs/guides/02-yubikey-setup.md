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

## 1. Enable KDF, then change the YubiKey PINs

Two things happen here, **in this order**, while the card is still empty:
turn on KDF, then change the default PINs.  Both must be done before any
subkey is moved onto the card in section 4.

### Enable KDF first (do this before anything else)

**KDF (Key Derived Function)** makes GnuPG hash your PIN on the host
*before* sending it to the card, so the PIN never travels over the
USB/PC-SC link or gets stored on the card in clear text.  Only the hash
is transmitted and stored.  Without KDF, anyone able to observe the link
to the reader (or a malicious reader) sees your PIN in plain text.

> **KDF can only be enabled on an empty card, and it must be turned on
> first.**
>
> The KDF setting can only be changed while the OpenPGP applet holds no
> keys.  Once you have run `keytocard` (section 4), any attempt to change
> it fails with:
>
> ```
> gpg: error for setup KDF: Conditions of use not satisfied
> ```
>
> Recovering from that means factory-resetting the OpenPGP applet
> (`ykman openpgp reset`), which **wipes the keys and the PINs** and
> forces you to redo this whole guide.  So enable KDF now, before the
> PIN change and before `keytocard`.

Requires YubiKey firmware 5.2.3+ (OpenPGP 3.4) and GnuPG 2.2.1+ -- both
are satisfied by the prerequisites above.

> **Insert your YubiKey now.**

```bash
gpg --card-edit
```

```
gpg/card> admin
gpg/card> kdf-setup
  (enter the Admin PIN -- default 12345678)
```

Confirm it took:

```bash
gpg --card-status | grep -i 'KDF setting'
```

```
KDF setting ......: on
```

> Enabling KDF re-hashes the PINs the card currently holds, so do it
> *before* you set your own PINs -- otherwise the change below has to be
> the first time the new hash format is written anyway.  Setting KDF first
> and changing PINs second (next step) is the clean order.

### Change the PINs

The default PINs are well-known and must be changed immediately.  Stay in
(or re-enter) `gpg --card-edit`:

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

## 3. Set the public-key URL on the card (recommended)

The card holds only your *private* keys.  Tools that need the public half --
this project's `make sign` / `make verify` and the in-image
`safe-yubikey-fetch-pubkey` -- run `gpg --card-edit > fetch`, which downloads
the public key from a **URL stored on the card**.  Setting that URL once makes
the public key self-bootstrapping on any fresh machine, instead of relying on a
keyserver lookup.

> Host your ASCII-armored public key somewhere durable and fetchable over HTTPS
> first -- your own web server, or a raw file URL such as
> `https://raw.githubusercontent.com/<you>/<repo>/main/pubkey.asc`.

```bash
gpg --card-edit
```

```
gpg/card> admin
gpg/card> url
  https://example.com/path/to/your-pubkey.asc
gpg/card> quit
```

Verify it was stored:

```bash
gpg --card-status | grep -i 'URL of public key'
```

> **`ykman` cannot set this field.**  The OpenPGP "URL of public key" data
> object is not exposed by any `ykman openpgp` command (verified against ykman
> 5.9.1 and Yubico's official OpenPGP command reference,
> <https://docs.yubico.com/software/yubikey/tools/ykman/OpenPGP_Commands.html>).
> `gpg --card-edit > admin > url` is the only supported way to set it.  If you
> have nowhere to host the key, leave the URL unset and rely on the keyserver
> fallback (`keyserver.ubuntu.com`) or import the public key from a file.

## 4. Move subkeys to YubiKey

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

## 5. Verify

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

## 6. Provision additional YubiKeys (optional -- same keys on several cards)

To keep the **same** subkeys on more than one YubiKey (e.g. a daily card and a
spare in a safe), you cannot simply repeat section 4: `keytocard` *moved* the
subkey private material onto the first card and left only **stubs** (pointers to
that card's serial) in this keyring.  A stub cannot be moved, so for **each**
additional YubiKey you must reset GnuPG and re-import the real private keys from
your backup.

> **Have your encrypted backup USB ready, and insert the next YubiKey.**

Repeat these steps for every additional card:

1. **Reset the GnuPG environment** so the stubs pointing at the previous card
   are cleared (otherwise `keytocard` has only stubs to work with):

   ```bash
   gpgconf --kill all      # release the previous card from gpg-agent/scdaemon
   rm -rf ~/.gnupg         # this live image wipes it on reboot anyway
   ```

2. **Re-import the private keys from your backup**, mounting the encrypted
   backup read-only as in [06-recovery.md](06-recovery.md):

   ```bash
   sudo cryptsetup open /dev/sdX1 backup
   sudo mount -o ro /dev/mapper/backup /mnt

   gpg --import /mnt/"${KEYID}-master.key"    # master + subkeys; needed for keytocard

   sudo umount /mnt
   sudo cryptsetup close backup
   ```

   > **Do NOT import `${KEYID}-revoke.asc`.**  That file is the *revocation
   > certificate*.  Importing it marks the key as **revoked** in this keyring,
   > and every later `keytocard`, export, or publish would then carry the
   > revocation -- permanently disabling the key for everyone.  Leave it
   > untouched in your backup; it is only ever imported when you deliberately
   > retire the key (see [05-revoke-keys.md](05-revoke-keys.md)).

3. **Enable KDF and change the new card's PINs** (section 1) -- every fresh
   YubiKey ships with KDF off and the well-known default PINs.  KDF must be
   enabled now, before step 4, because it cannot be changed once subkeys are on
   the card.

4. **Move the subkeys onto this card** exactly as in section 4 above
   (`key 1` → `keytocard` → 1, `key 2` → `keytocard` → 2,
   `key 3` → `keytocard` → 3, then `save`).

5. **Verify** as in section 5 (`gpg --card-status` shows all three slots).

Once every YubiKey is provisioned, continue with the public-key export and the
cleanup below -- they remove the re-imported private material from this session.

## 7. Export your public key for daily use

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

## 8. Clean up the safe-image

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
