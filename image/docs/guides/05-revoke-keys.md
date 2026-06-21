# Revoke Keys

How to revoke your master key or individual subkeys.  Revocation is
permanent and should only be done when a key is compromised, lost, or
being replaced.

> **Environment: safe-image (air-gapped)**
>
> Revocation requires the master key.  Import it from your offline
> backup, perform the revocation, export the updated public key, then
> remove the master key.

## When to revoke

| Scenario | Action | Guide |
|----------|--------|-------|
| YubiKey lost or stolen | Revoke all subkeys, create new ones | This guide → [01](01-generate-keys.md) step 2 → [02](02-yubikey-setup.md) |
| YubiKey PIN compromised | Revoke all subkeys, factory-reset YubiKey, create new subkeys | This guide → [06](06-recovery.md) → [01](01-generate-keys.md) step 2 |
| Master key compromised | Revoke the master key (nuclear option) | This guide (section below) |
| Replacing a single subkey | Revoke that subkey, add a new one | This guide → [01](01-generate-keys.md) step 2 |
| Routine rotation | Revoke old subkeys after new ones are deployed | This guide |

## Prerequisites

- safe-image booted in offline mode
- Master key backup USB available

## Before you begin

> **STOP -- Verify you are offline.**
>
> ```bash
> ip link | grep 'state UP'
> ```
>
> No interfaces should be UP.

## 1. Import master key

> **Insert your encrypted BACKUP USB now.**

```bash
lsblk   # identify the device
sudo cryptsetup open /dev/sdX1 backup
sudo mount -o ro /dev/mapper/backup /mnt

gpg --import /mnt/KEYID-master.key

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the BACKUP USB now.**

## Revoke a subkey

### 2. Select and revoke

```bash
gpg --edit-key "${KEYID}"
```

List subkeys to identify which to revoke:

```
gpg> list
```

Select the subkey (e.g. subkey 1):

```
gpg> key 1
```

Revoke it:

```
gpg> revkey
```

When prompted:
1. Confirm with **y**
2. Select a reason:
   - **1** -- Key has been compromised
   - **2** -- Key is superseded
   - **3** -- Key is no longer used
3. Enter an optional description
4. Enter your master key passphrase

Repeat for other subkeys if needed (`key 2`, `key 3`).

```
gpg> save
```

### 3. Export the updated public key

```bash
gpg --armor --export "${KEYID}" > "${KEYID}-public.key"
```

### 4. Remove master key from this session

```bash
gpg --delete-secret-keys "${KEYID}"
# keep only the card stubs
gpg --card-status
```

### 5. Create replacement subkeys (if needed)

Follow [01-generate-keys.md](01-generate-keys.md) step 2 to add new
subkeys (you will need to import the master key again), then
[02-yubikey-setup.md](02-yubikey-setup.md) to move them to the YubiKey.

### 6. Update your backups

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

### 7. Distribute the revocation

> **STOP -- You are about to leave the air-gapped environment.**
>
> Carry the updated public key on a regular (unencrypted) USB stick.
> Make sure your encrypted backup USBs are stored safely before
> proceeding.

> **Environment: any machine (daily workstation)**

On your daily machine, import the updated public key and publish:

```bash
gpg --import /run/media/$USER/<usb>/KEYID-public.key
```

> **You must publish to keyservers immediately** so others stop using
> the revoked subkeys.

```bash
gpg --keyserver hkps://keyserver.ubuntu.com:443 --send-keys "${KEYID}"
```

Anyone who refreshes your key will see the subkey is revoked.

---

## Revoke the master key

This is the nuclear option.  It permanently invalidates your entire key
(master + all subkeys).  Only do this if the master key is compromised.

> **Environment: safe-image (air-gapped)**
>
> **STOP -- Verify you are offline before importing master key
> material.**

### Option A: Use the pre-generated revocation certificate

If you created a revocation certificate during key generation:

> **Insert your encrypted BACKUP USB now.**

```bash
sudo cryptsetup open /dev/sdX1 backup
sudo mount -o ro /dev/mapper/backup /mnt

gpg --import /mnt/KEYID-revoke.asc

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the BACKUP USB now.**

### Option B: Generate a new revocation certificate

If you have the master key but not the revocation certificate:

> **Insert your encrypted BACKUP USB now.**

```bash
sudo cryptsetup open /dev/sdX1 backup
sudo mount -o ro /dev/mapper/backup /mnt

gpg --import /mnt/KEYID-master.key

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the BACKUP USB now.**

```bash
gpg --output "${KEYID}-revoke.asc" --gen-revoke "${KEYID}"
gpg --import "${KEYID}-revoke.asc"
```

### Export the revoked public key

```bash
gpg --armor --export "${KEYID}" > "${KEYID}-public.key"
```

### Distribute the revocation

> **Environment: any machine (daily workstation)**

```bash
gpg --import /run/media/$USER/<usb>/KEYID-public.key
```

> **You must publish to keyservers immediately.**  Until you do,
> others may still encrypt to your compromised key.

```bash
gpg --keyserver hkps://keyserver.ubuntu.com:443 --send-keys "${KEYID}"
```

After this, anyone who fetches your key will see it is revoked.
You need to generate an entirely new master key starting from
[01-generate-keys.md](01-generate-keys.md).

## After revoking

- Ensure **both** backup USBs carry the updated public key (with the
  revocation signature embedded)
- If you revoked subkeys only: create new subkeys and move them to
  the YubiKey (all on the safe-image)
- If you revoked the master key: start fresh with
  [01-generate-keys.md](01-generate-keys.md)
- Notify anyone who relies on your key
