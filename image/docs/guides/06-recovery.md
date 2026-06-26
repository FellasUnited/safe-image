# Backup, Restore, and Recovery

Procedures for managing your offline backups, restoring keys to a new
YubiKey, and recovering from a lost or locked device.

## What to back up

| File | Contains | How to create |
|------|----------|---------------|
| `KEYID-master.key` | Master + subkey private keys | `gpg --armor --export-secret-keys KEYID` |
| `KEYID-subkeys.key` | Subkey private keys only | `gpg --armor --export-secret-subkeys KEYID` |
| `KEYID-public.key` | Public key (master + subkeys) | `gpg --armor --export KEYID` |
| `KEYID-revoke.asc` | Revocation certificate | `gpg --gen-revoke KEYID` |

**All four files must exist on at least two encrypted USB sticks stored
in physically separate locations.**  If one backup is lost or damaged,
the other is your only path to recovery.

## Create an encrypted backup USB

> **Environment: safe-image (air-gapped)**
>
> **STOP -- Verify you are offline.**
>
> ```bash
> ip link | grep 'state UP'
> ```

### Format and encrypt

> **Insert the USB stick you want to use as a backup.**

```bash
lsblk   # identify the device -- WRONG device = DATA LOSS
```

```bash
sudo cryptsetup luksFormat /dev/sdX1
sudo cryptsetup open /dev/sdX1 backup
sudo mkfs.ext4 /dev/mapper/backup
sudo mount /dev/mapper/backup /mnt

sudo cp KEYID-master.key KEYID-subkeys.key \
       KEYID-public.key KEYID-revoke.asc /mnt/
sync

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the USB stick.  Label it clearly (e.g. "GPG Backup A").**

> **You must create a SECOND copy on a different USB stick.**
> Repeat the above with a fresh USB and label it differently
> (e.g. "GPG Backup B").  Store each in a different physical
> location.

### Open an existing encrypted backup

```bash
sudo cryptsetup open /dev/sdX1 backup
sudo mount -o ro /dev/mapper/backup /mnt
ls /mnt/
```

Always mount read-only (`-o ro`) unless you need to write.

## Restore to a new YubiKey

> **Environment: safe-image (air-gapped)**
>
> Restoring keys requires the master key.  The entire process must
> happen offline.

> **STOP -- Verify you are offline.**
>
> ```bash
> ip link | grep 'state UP'
> ```

### 1. Import the backup

> **Insert your encrypted BACKUP USB now.**

```bash
lsblk
sudo cryptsetup open /dev/sdX1 backup
sudo mount -o ro /dev/mapper/backup /mnt

gpg --import /mnt/KEYID-master.key
gpg --import /mnt/KEYID-public.key

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the BACKUP USB now.**

Set `KEYID` for the rest of this guide (the live image is amnesic, so it is
unset on a fresh boot):

```bash
export KEYID=$(gpg --list-keys --with-colons | awk -F: '/^fpr/ { print $10; exit }')
echo "$KEYID"   # should print your 40-char fingerprint
```

Set trust:

```bash
gpg --edit-key "${KEYID}"
gpg> trust
# select 5 (ultimate)
gpg> quit
```

### 2. Set up the new YubiKey

> **Insert the new YubiKey now.**

Follow [02-yubikey-setup.md](02-yubikey-setup.md):

1. Enable KDF and change PINs (step 1) -- KDF must be turned on while the
   card is still empty, before `keytocard`
2. Move subkeys to card with `keytocard` (step 4)
3. Remove master key from the keyring (step 8)

### 3. Export the updated public key

```bash
gpg --armor --export "${KEYID}" > "${KEYID}-public.key"
```

> **Insert a regular (unencrypted) USB stick now** to carry the public
> key to your daily machine.

```bash
cp "${KEYID}-public.key" /run/media/$USER/<usb>/
sync
```

> **Remove the USB stick.**

### 4. Update your backups with the new public key

The public key now references the new card serial number.  Both
backups should carry it.

> **Insert your PRIMARY backup USB now.**

```bash
sudo cryptsetup open /dev/sdX1 backup
sudo mount /dev/mapper/backup /mnt

sudo cp "${KEYID}-public.key" /mnt/
sync

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the PRIMARY backup USB now.**

> **Insert your DUPLICATE backup USB now.**

```bash
sudo cryptsetup open /dev/sdY1 backup
sudo mount /dev/mapper/backup /mnt

sudo cp "${KEYID}-public.key" /mnt/
sync

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the DUPLICATE backup USB now.**

### 5. Import on your daily machine

> **Environment: any machine (daily workstation)**

```bash
gpg --import /run/media/$USER/<usb>/KEYID-public.key
gpg --card-status
```

Publish the updated key so others reference the new card serial:

```bash
gpg --keyserver hkps://keyserver.ubuntu.com:443 --send-keys "${KEYID}"
```

## Factory-reset a YubiKey

> **Environment: safe-image (air-gapped)**
>
> After a factory reset you will need to re-provision the YubiKey
> from your backup.

> **STOP -- Verify your backup USBs exist and are intact before
> resetting.**  After the reset all key material on the card is gone.

**This erases all OpenPGP keys and PINs from the YubiKey.**

Use this when the Admin PIN is blocked (3 wrong attempts) or you
want to start fresh.

```bash
ykman openpgp reset
```

Or via `gpg --card-edit`:

```bash
gpg --card-edit
gpg/card> admin
gpg/card> factory-reset
gpg/card> quit
```

After reset, all PINs return to defaults (`123456` / `12345678`)
and all key slots are empty.  Follow "Restore to a new YubiKey"
above to re-provision.

## Lost YubiKey procedure

> **Environment: safe-image (air-gapped)**
>
> **Act quickly** -- the subkeys on the lost card may be used by
> anyone who knows your User PIN.

1. Boot the safe-image offline
2. **Verify you are offline** (`ip link | grep 'state UP'`)
3. Insert your encrypted backup USB and import your master key
4. **Remove the backup USB** once the import is done
5. Revoke the compromised subkeys (see [05-revoke-keys.md](05-revoke-keys.md))
6. Create new subkeys ([01-generate-keys.md](01-generate-keys.md) step 2)
7. Move them to a new YubiKey ([02-yubikey-setup.md](02-yubikey-setup.md))
8. Export the updated public key
9. Update **both** backup USBs with the new public key

Then, carry the updated public key to your daily machine:

> **Environment: any machine (daily workstation)**

10. Import the updated public key
11. **Publish to keyservers immediately:**

```bash
gpg --keyserver hkps://keyserver.ubuntu.com:443 --send-keys "${KEYID}"
```

12. Update `~/.ssh/authorized_keys` on any remote hosts

## Verify your backup periodically

> **Environment: safe-image (air-gapped)**

At least once a year, boot the safe-image and verify **both**
backup USBs are readable.

> **Insert BACKUP USB (primary) now.**

```bash
sudo cryptsetup open /dev/sdX1 backup
sudo mount -o ro /dev/mapper/backup /mnt

export GNUPGHOME=$(mktemp -d)
gpg --import /mnt/KEYID-master.key
gpg --list-secret-keys

rm -rf "${GNUPGHOME}"
unset GNUPGHOME

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the USB.  Primary backup verified.**

> **Insert BACKUP USB (duplicate) now.**

Repeat the same verification:

```bash
sudo cryptsetup open /dev/sdY1 backup
sudo mount -o ro /dev/mapper/backup /mnt

export GNUPGHOME=$(mktemp -d)
gpg --import /mnt/KEYID-master.key
gpg --list-secret-keys

rm -rf "${GNUPGHOME}"
unset GNUPGHOME

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the USB.  Duplicate backup verified.**
>
> If either backup fails verification, immediately create a fresh
> copy from the working one.
