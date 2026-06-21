# Extend Subkey Expiry

Renew your subkeys before they expire.  This requires the master key,
so it must be done on the air-gapped safe-image.

> **Environment: safe-image (air-gapped)**
>
> The master key is needed to re-certify subkeys with new expiry
> dates.  Import it from your offline backup, extend, export the
> updated public key, then remove the master key.

## Prerequisites

- safe-image booted in offline mode
- Master key backup USB available (`KEYID-master.key`)
- Know your master key passphrase

## Before you begin

The new expiry you set is recorded against the current system clock, so make
sure the time is correct first.  Sync it over NTP in a brief online window,
then return offline:

```bash
sudo safe-netmode online           # brief online window for NTP only
sudo timedatectl set-ntp true
timedatectl status               # wait for: System clock synchronized: yes
date -u                          # sanity-check the date/time (UTC)
sudo safe-netmode offline          # disable the network again
```

> **STOP -- Verify you are offline.**
>
> ```bash
> ip link | grep 'state UP'
> ```
>
> No interfaces should be UP.

## 1. Import the master key

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

## 2. Check current expiry

```bash
gpg --list-keys --keyid-format long "${KEYID}"
```

Note which subkeys are near expiry.

## 3. Extend each subkey

```bash
gpg --edit-key "${KEYID}"
```

### Select and extend each subkey

```
gpg> key 1
gpg> expire
```

Enter the new expiry period (e.g. `1y` for one year from today).
Enter your master key passphrase when prompted.

```
gpg> key 1
gpg> key 2
gpg> expire
```

Repeat for each subkey (`key 1`, `key 2`, `key 3`).

```
gpg> save
```

## 4. Update the YubiKey stubs

The YubiKey itself does not store expiry information -- it's in the
public key.  Refresh the local stubs:

```bash
gpg --card-status
```

## 5. Export the updated public key

```bash
gpg --armor --export "${KEYID}" > "${KEYID}-public.key"
```

## 6. Remove the master key

```bash
gpg --delete-secret-keys "${KEYID}"
```

Confirm deleting only the master key.  Verify:

```bash
gpg --list-secret-keys "${KEYID}"
# should show sec# (master absent) and ssb> (card stubs)
```

## 7. Update your backups

> **Insert your PRIMARY backup USB now.**

Mount the encrypted backup USB and replace the old public key:

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
>
> Both backups must carry the updated public key.

Repeat:

```bash
sudo cryptsetup open /dev/sdY1 backup
sudo mount /dev/mapper/backup /mnt

sudo cp "${KEYID}-public.key" /mnt/
sync

sudo umount /mnt
sudo cryptsetup close backup
```

> **Remove the DUPLICATE backup USB now.**

## 8. Carry the public key to your daily machine

> **Insert a regular (unencrypted) USB stick now.**

```bash
cp "${KEYID}-public.key" /run/media/$USER/<usb>/
sync
```

> **Remove the USB stick.**

## 9. Distribute the updated public key

> **Environment: any machine (daily workstation)**
>
> The remaining steps are done on your network-connected machine.

Import the updated public key:

```bash
gpg --import /run/media/$USER/<usb>/KEYID-public.key
```

Publish to keyservers so anyone who verifies your signatures will see
the new expiry dates:

```bash
gpg --keyserver hkps://keyserver.ubuntu.com --send-keys "${KEYID}"
```

> **You must publish to keyservers every time you extend expiry.**
> Otherwise, others will see your subkeys as expired and reject your
> signatures.

Share the updated public key with anyone who verifies your signatures
and does not use keyservers.
