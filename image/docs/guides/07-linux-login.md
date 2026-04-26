# YubiKey for Linux Login and Sudo

Use your YubiKey's FIDO2 capability to authenticate to Fedora --
login, sudo, and screen unlock -- instead of (or in addition to)
a password.

> **Environment: any machine (your daily Fedora machine)**
>
> This guide uses the YubiKey's **FIDO2 applet**, which is separate
> from the OpenPGP applet used in guides 01-06.  FIDO2 has its own
> PIN (set during first registration).

## Prerequisites

- Fedora with a user account
- YubiKey 5 series with FIDO2 support
- A backup YubiKey (strongly recommended -- if you require the key
  for login and lose it, you can be locked out)

## 1. Install pam-u2f

```bash
sudo dnf install pam-u2f pamu2fcfg
```

## 2. Set a FIDO2 PIN (if not already set)

If you have never used FIDO2 on this YubiKey, set a PIN now:

```bash
ykman fido access change-pin
```

You will be prompted to create a new PIN.  This PIN is separate from
the OpenPGP User/Admin PINs.

## 3. Register your YubiKey

> **Insert your PRIMARY YubiKey now.**

Create the credential store and register the key:

```bash
mkdir -p ~/.config/Yubico
pamu2fcfg > ~/.config/Yubico/u2f_keys
```

You will be prompted for your FIDO2 PIN, then asked to touch the
YubiKey.

### Register a backup YubiKey

> **Remove your primary YubiKey.  Insert your BACKUP YubiKey now.**

Append the backup key to the same file:

```bash
pamu2fcfg -n >> ~/.config/Yubico/u2f_keys
```

Touch the backup key when prompted.

> **Remove the backup YubiKey.  Re-insert your primary YubiKey.**

> **IMPORTANT:** Always register at least two keys.  If you require
> the YubiKey for login (`required` mode) and lose your only
> registered key, you will be locked out of your account.

## 4. Choose an authentication mode

There are two approaches:

| Mode | PAM keyword | Behavior |
|------|-------------|----------|
| Second factor | `required` | Password **AND** YubiKey touch required |
| Passwordless | `sufficient` | YubiKey touch **OR** password (either works) |

`required` is more secure.  `sufficient` is more convenient.

## 5. Configure PAM

> **STOP -- Before editing PAM, open a separate root shell and keep
> it running.**  If you misconfigure PAM, this shell is your only way
> to fix it without rebooting.
>
> ```bash
> sudo -i
> ```

### For sudo

Edit `/etc/pam.d/sudo`:

**Second factor** (password + YubiKey):

```bash
sudo sed -i '1 a auth       required   pam_u2f.so' /etc/pam.d/sudo
```

This inserts `auth required pam_u2f.so` as the second line.  After
entering your password, you will be asked to touch the YubiKey.

**Passwordless** (YubiKey alone):

```bash
sudo sed -i '1 a auth       sufficient pam_u2f.so' /etc/pam.d/sudo
```

Touch the YubiKey and you are in -- no password needed.

### For GDM login (GNOME)

Edit `/etc/pam.d/gdm-password`:

```bash
sudo sed -i '/^auth.*pam_gnome_keyring.so/i auth       required   pam_u2f.so' \
    /etc/pam.d/gdm-password
```

### For console login

Edit `/etc/pam.d/login`:

```bash
sudo sed -i '1 a auth       required   pam_u2f.so' /etc/pam.d/login
```

### For screen unlock (GNOME)

Edit `/etc/pam.d/gdm-fingerprint` (also used for GNOME screen
unlock):

```bash
sudo sed -i '1 a auth       required   pam_u2f.so' /etc/pam.d/gdm-fingerprint
```

## 6. Test

**Test sudo first** (lowest risk -- your backup root shell can fix
mistakes):

```bash
sudo echo "YubiKey auth works"
```

You should see a "Please touch the device" prompt.  Touch the YubiKey.

**Test login** only after sudo works.  Lock your screen and unlock it,
or log out and log back in.

## 7. System-wide credential store (optional)

By default, credentials are in `~/.config/Yubico/u2f_keys` (per-user).
For a system-wide store:

```bash
sudo mkdir -p /etc/u2f_keys
sudo mv ~/.config/Yubico/u2f_keys /etc/u2f_keys/$USER
```

Then update the PAM lines to use `authfile`:

```
auth required pam_u2f.so authfile=/etc/u2f_keys/%u
```

## Troubleshooting

### "No U2F device available"

```bash
fido2-token -L
```

If nothing is listed, check that the YubiKey is inserted and that
`pcscd` is not holding the device:

```bash
gpgconf --kill scdaemon
fido2-token -L
```

### SELinux denial

If `pam_u2f.so` fails with an AVC denial:

```bash
sudo ausearch -m avc -ts recent
```

Temporarily set SELinux to permissive to confirm:

```bash
sudo setenforce 0
# test login
sudo setenforce 1
```

If it works in permissive mode, generate a policy module:

```bash
sudo ausearch -m avc -ts recent | audit2allow -M pam_u2f_local
sudo semodule -i pam_u2f_local.pp
```

### Debug logging

Add `debug` to the PAM line for verbose output in the journal:

```
auth required pam_u2f.so debug
```

Then check:

```bash
sudo journalctl -e | grep pam_u2f
```

Remove `debug` once the issue is resolved.

### Locked out

If you misconfigured PAM and cannot log in:

1. Reboot and select a previous kernel in GRUB
2. Append `single` or `init=/bin/bash` to the kernel command line
3. Mount the root filesystem read-write: `mount -o remount,rw /`
4. Edit the PAM file to remove or comment out the `pam_u2f.so` line
5. Reboot normally

Alternatively, boot from a live USB and edit the PAM files directly.
