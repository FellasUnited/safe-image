# YubiKey for LUKS Disk Encryption

Use your YubiKey's FIDO2 capability to unlock a LUKS-encrypted disk
at boot -- touch the key instead of typing a passphrase.

> **Environment: any machine (your daily Fedora machine with LUKS)**
>
> This guide uses the YubiKey's **FIDO2 applet**, which is separate
> from the OpenPGP applet used in guides 01-06.  FIDO2 has its own
> PIN (set during first registration or in
> [07-linux-login.md](07-linux-login.md)).

## Prerequisites

- Fedora with a LUKS2-encrypted root (or other) volume
- systemd 248+ (Fedora 34+; check with `systemctl --version`)
- YubiKey 5 series with FIDO2 support
- A backup YubiKey (strongly recommended)
- The existing LUKS passphrase (you will need it during enrollment)

> **IMPORTANT:** Do **not** remove the passphrase keyslot after
> enrolling the YubiKey.  Keep it as an emergency fallback in case
> the YubiKey is lost, broken, or unavailable.

## 1. Identify your LUKS device

```bash
lsblk -f
```

Find the encrypted partition -- usually something like
`/dev/nvme0n1p3` or `/dev/sda3`.  Confirm it is LUKS2:

```bash
sudo cryptsetup luksDump /dev/<device>
```

Look for `Version: 2` in the output.  `systemd-cryptenroll` requires
LUKS2; if you see Version 1, you must convert first (see
Troubleshooting below).

Export the device path for the rest of this guide:

```bash
export LUKSDEV="/dev/<device>"
```

## 2. Set a FIDO2 PIN (if not already set)

If you have not set a FIDO2 PIN (e.g. you skipped
[07-linux-login.md](07-linux-login.md)):

```bash
ykman fido access change-pin
```

## 3. Enroll the YubiKey

> **Insert your PRIMARY YubiKey now.**

```bash
sudo systemd-cryptenroll \
    --fido2-device=auto \
    --fido2-with-client-pin=true \
    --fido2-with-user-presence=true \
    "${LUKSDEV}"
```

You will be prompted for:
1. The existing LUKS passphrase (to authorize adding a new keyslot)
2. The FIDO2 PIN
3. A physical touch on the YubiKey

Options explained:

| Flag | Default | Effect |
|------|---------|--------|
| `--fido2-with-client-pin=true` | true | Require the FIDO2 PIN at every unlock |
| `--fido2-with-user-presence=true` | true | Require a physical touch at every unlock |

Both should remain `true` for maximum security.

Verify the new keyslot was created:

```bash
sudo cryptsetup luksDump "${LUKSDEV}"
```

You should see a new `systemd-fido2` token entry.

### Enroll a backup YubiKey

> **Remove your primary YubiKey.  Insert your BACKUP YubiKey now.**

```bash
sudo systemd-cryptenroll \
    --fido2-device=auto \
    --fido2-with-client-pin=true \
    --fido2-with-user-presence=true \
    "${LUKSDEV}"
```

This creates a second FIDO2 keyslot.  Either key can unlock the disk.

> **Remove the backup YubiKey.  Re-insert your primary YubiKey.**

## 4. Update /etc/crypttab

Tell the initramfs to use FIDO2 for unlocking.  Find your volume's
entry:

```bash
cat /etc/crypttab
```

A typical line looks like:

```
luks-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx none discard
```

Add `fido2-device=auto` to the options column:

```bash
sudo sed -i 's/discard$/discard,fido2-device=auto/' /etc/crypttab
```

If the line ends with something other than `discard`, append
`,fido2-device=auto` to the existing options.  The result should look
like:

```
luks-xxxxxxxx-... UUID=xxxxxxxx-... none discard,fido2-device=auto
```

## 5. Regenerate the initramfs

This is critical -- without it, the initramfs will not include the
FIDO2 unlock logic:

```bash
sudo dracut --regenerate-all --force
```

## 6. Reboot and test

```bash
sudo reboot
```

At boot, Plymouth will prompt for the FIDO2 PIN (not your old LUKS
passphrase).  Enter the PIN, then touch the YubiKey when the LED
blinks.

> If you don't see the FIDO2 prompt, press **Esc** to switch from
> the graphical Plymouth to the text prompt -- the FIDO2 dialog may
> be hidden behind the splash screen.

If the YubiKey is not inserted at boot, the system will fall back to
the passphrase prompt (as long as you kept the passphrase keyslot).

## Removing a FIDO2 keyslot

To unenroll a specific YubiKey (e.g. a lost or replaced key):

```bash
sudo cryptsetup luksDump "${LUKSDEV}"
```

Identify the FIDO2 keyslot number (e.g. slot 1 or 2), then:

```bash
sudo systemd-cryptenroll --wipe-slot=<slot-number> "${LUKSDEV}"
```

> **Never wipe all FIDO2 slots and the passphrase slot at the same
> time.**  Always keep at least one way to unlock the volume.

## Troubleshooting

### Plymouth shows passphrase prompt instead of FIDO2

1. Verify `/etc/crypttab` has `fido2-device=auto`
2. Verify initramfs was regenerated (`sudo dracut --regenerate-all --force`)
3. Check that the YubiKey is inserted before the boot prompt appears
4. Press **Esc** to check if the FIDO2 prompt is behind the splash

### LUKS version is 1, not 2

Convert to LUKS2 (backup your data first):

```bash
sudo cryptsetup convert --type luks2 "${LUKSDEV}"
```

### "No FIDO2 device found"

```bash
fido2-token -L
```

If nothing is listed:

```bash
gpgconf --kill scdaemon
fido2-token -L
```

The `scdaemon` (smartcard daemon from GnuPG) can hold an exclusive
lock on the YubiKey.  Killing it releases the device for FIDO2 use.

### Multiple LUKS volumes

Repeat the enrollment and `/etc/crypttab` edit for each encrypted
volume.  Each volume gets its own FIDO2 keyslot(s).

### Checking enrolled FIDO2 tokens

```bash
sudo systemd-cryptenroll "${LUKSDEV}"
```

This lists all keyslots and their types.
