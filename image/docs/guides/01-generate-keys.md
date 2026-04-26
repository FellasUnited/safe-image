# Generate GPG Keys

Create a new GPG master key with Ed25519 and three subkeys for signing,
encryption, and authentication.

> **Environment: safe-image (air-gapped)**
>
> This entire guide must be performed on the safe-image booted
> in offline mode.  Private key material must never exist on a
> network-connected machine.

## Prerequisites

- safe-image booted (offline mode -- the default)
- Two USB sticks for encrypted backups (primary + duplicate)
- A YubiKey 5 series (firmware 5.2.3+ for Ed25519)

## Before you begin

> **STOP -- Verify you are offline.**
>
> ```bash
> ip link | grep 'state UP'
> ```
>
> No interfaces should be UP.  If any are, run `sudo si-netmode offline`.

## 1. Create the master key (certify only)

The master key only certifies subkeys -- it does not sign, encrypt, or
authenticate.  It will be backed up offline and never stored on the
YubiKey.

```bash
gpg --expert --full-gen-key
```

When prompted:

1. Select **(11) ECC (set your own capabilities)**
2. Toggle capabilities until only **Certify** remains:
   - Type `s` to disable Sign
   - Type `q` to finish
3. Select **Curve 25519** (option 1)
4. Set expiry to **0 (does not expire)** -- subkeys will expire instead
5. Enter your real name and email
6. Set a strong passphrase (you will only need it when certifying)

Note your key ID:

```bash
gpg --list-keys --keyid-format long
```

Export the key ID for the rest of this guide:

```bash
export KEYID="<your-40-char-fingerprint>"
```

## 2. Add subkeys

```bash
gpg --expert --edit-key "${KEYID}"
```

### Signing subkey

```
gpg> addkey
```

1. Select **(11) ECC (set your own capabilities)**
2. Toggle until only **Sign** remains (`e` to disable Encrypt if shown, `q` to finish)
3. Select **Curve 25519**
4. Set expiry to **1y** (one year -- renew annually)
5. Confirm

### Encryption subkey

```
gpg> addkey
```

1. Select **(12) ECC (encrypt only)**
2. Select **Curve 25519**
3. Set expiry to **1y**
4. Confirm

### Authentication subkey

```
gpg> addkey
```

1. Select **(11) ECC (set your own capabilities)**
2. Toggle until only **Authenticate** remains
   (`s` to disable Sign, `a` to enable Authenticate, `q` to finish)
3. Select **Curve 25519**
4. Set expiry to **1y**
5. Confirm

```
gpg> save
```

## 3. Verify

```bash
gpg --list-secret-keys --keyid-format long "${KEYID}"
```

You should see:

```
sec   ed25519/XXXXXXXXXXXXXXXX  ...  [C]
ssb   ed25519/YYYYYYYYYYYYYYYY  ...  [S]  expires: ...
ssb   cv25519/ZZZZZZZZZZZZZZZZ  ...  [E]  expires: ...
ssb   ed25519/WWWWWWWWWWWWWWWW  ...  [A]  expires: ...
```

## 4. Generate a revocation certificate

```bash
gpg --output "${KEYID}-revoke.asc" --gen-revoke "${KEYID}"
```

Select reason **0 (No reason specified)**.  This certificate can
irrevocably disable your key -- treat it as seriously as the master key.

## 5. Back up everything

Before moving keys to the YubiKey (which is destructive -- the local
copy is replaced with a stub), back up the full keyring to **two**
encrypted USB sticks.

### Export the keys

```bash
gpg --armor --export-secret-keys "${KEYID}" > "${KEYID}-master.key"
gpg --armor --export-secret-subkeys "${KEYID}" > "${KEYID}-subkeys.key"
gpg --armor --export "${KEYID}" > "${KEYID}-public.key"
```

### Prepare your backup USBs

If your USB sticks are not yet LUKS-encrypted, format them now by
following the "Create an encrypted backup USB" section in
[06-recovery.md](06-recovery.md), then return here to copy the keys.

### Write to your PRIMARY backup USB

> **Insert your PRIMARY backup USB stick now.**

```bash
lsblk   # identify the device -- be careful!
sudo cryptsetup open /dev/sdX1 backup
sudo mount /dev/mapper/backup /mnt

sudo cp "${KEYID}"-{master,subkeys,public}.key "${KEYID}-revoke.asc" /mnt/
sync

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the PRIMARY backup USB now.**

### Write to your DUPLICATE backup USB

> **Insert your DUPLICATE backup USB stick now.**
>
> You must keep at least two copies of your master key in physically
> separate locations.  If one is lost or damaged, the other is your
> only way to create new subkeys, extend expiry, or revoke.

```bash
sudo cryptsetup open /dev/sdY1 backup
sudo mount /dev/mapper/backup /mnt

sudo cp "${KEYID}"-{master,subkeys,public}.key "${KEYID}-revoke.asc" /mnt/
sync

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the DUPLICATE backup USB now.**
>
> Store each backup in a different physical location (e.g. home safe
> and bank deposit box).

## Next steps

- [02-yubikey-setup.md](02-yubikey-setup.md) -- move subkeys to YubiKey
  (still on the safe-image -- do not reboot yet)
