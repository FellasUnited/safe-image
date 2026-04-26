# Daily GPG Operations

Using your YubiKey for signing, encryption, and SSH on your regular
machine.

> **Environment: any machine (your daily workstation/laptop)**
>
> None of these operations require the master key.  They only use the
> subkeys stored on your YubiKey.  The YubiKey must be inserted.

## Setting up a machine

These steps apply to **every** machine where you want to use the
YubiKey -- your first daily workstation, a second laptop, a work
machine, etc.  Repeat them on each new system.

### Import your public key

Pick one method:

**From a USB stick** (first machine, or if you don't use keyservers):

> **Insert the USB stick with your public key.**

```bash
gpg --import /run/media/$USER/<usb>/KEYID-public.key
```

> **Remove the USB stick.**

**From a keyserver** (if you already published it):

```bash
gpg --keyserver hkps://keys.openpgp.org --recv-keys "${KEYID}"
```

**From another machine** (copy the file over any way you like):

```bash
gpg --import KEYID-public.key
```

Set trust:

```bash
gpg --edit-key "${KEYID}"
gpg> trust
# select 5 (ultimate)
gpg> quit
```

### Fetch card stubs

Insert the YubiKey and let GPG create the stubs that link each subkey
to the card (see [02-yubikey-setup.md](02-yubikey-setup.md#what-are-stubs)
for details on what stubs are):

```bash
gpg --card-status
```

Verify:

```bash
gpg --list-secret-keys --keyid-format long "${KEYID}"
```

You should see `sec#` (master absent) and `ssb>` for each subkey.
No private key material exists on this machine -- the stubs just
redirect operations to the YubiKey.

### Publish your public key to keyservers

> **Do this on your first machine only.** You only need to publish
> once (and again after any change -- expiry extension, revocation,
> etc.).

```bash
gpg --keyserver hkps://keys.openpgp.org --send-keys "${KEYID}"
```

`keys.openpgp.org` will send a verification email to the UID address
on the key.  Confirm it to make the key discoverable by email search.

### Configure gpg-agent

`gpg-agent` replaces both the GPG passphrase agent and `ssh-agent`.
Enable SSH support so the authentication subkey works as an SSH key:

```bash
mkdir -p ~/.gnupg
cat > ~/.gnupg/gpg-agent.conf << 'EOF'
enable-ssh-support
default-cache-ttl 600
max-cache-ttl 7200
pinentry-program /usr/bin/pinentry-curses
EOF
```

> On GNOME/Wayland you may prefer `pinentry-gnome3` instead of
> `pinentry-curses`.  On a headless/SSH session, `pinentry-curses` or
> `pinentry-tty` is required.

Add to your shell profile (`~/.bashrc` or `~/.bash_profile`):

```bash
export GPG_TTY="$(tty)"
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
```

The `SSH_AUTH_SOCK` line tells SSH to talk to `gpg-agent` instead of
`ssh-agent`.  Every `ssh` or `git+ssh` connection will use the
YubiKey's authentication subkey.

Disable the default `ssh-agent` so it doesn't conflict:

```bash
systemctl --user disable --now ssh-agent.service 2>/dev/null || true
```

Reload:

```bash
gpgconf --kill gpg-agent
source ~/.bashrc
```

### Configure Git signing

Tell Git to use your GPG key for commits and tags:

```bash
git config --global user.signingkey "${KEYID}"
git config --global commit.gpgsign true
git config --global tag.gpgsign true
```

Every `git commit` and `git tag` will trigger the YubiKey -- you will
be prompted for your User PIN (the YubiKey LED blinks).

To let GitHub/GitLab verify your signed commits, upload your GPG
public key:

```bash
gpg --armor --export "${KEYID}"
```

Copy the output and paste it into:

- **GitHub:** Settings -> SSH and GPG keys -> New GPG key
- **GitLab:** Preferences -> GPG Keys

After uploading, signed commits will show a "Verified" badge.

### Configure SSH via gpg-agent

With `enable-ssh-support` in `gpg-agent.conf` (set above), your
YubiKey's authentication subkey (`[A]`) works as an SSH key.

#### Export your SSH public key

```bash
gpg --export-ssh-key "${KEYID}"
```

This prints an `ssh-ed25519 AAAA...` line.  Use it everywhere you
would normally put an SSH public key:

- **Remote servers:** append to `~/.ssh/authorized_keys`
- **GitHub:** Settings -> SSH and GPG keys -> New SSH key
- **GitLab:** Preferences -> SSH Keys

#### Configure `~/.ssh/config` for specific hosts (optional)

If you want to force SSH to use the YubiKey for certain hosts:

```
Host github.com
    IdentityAgent ~/.gnupg/S.gpg-agent.ssh

Host myserver.example.com
    IdentityAgent ~/.gnupg/S.gpg-agent.ssh
    User deploy
```

This is optional if you set `SSH_AUTH_SOCK` globally (see above), but
useful if you run multiple agents.

#### Verify SSH works

```bash
ssh-add -L
```

You should see your `ssh-ed25519` key listed.  Test a connection:

```bash
ssh -T git@github.com
# should print: Hi <username>! You've successfully authenticated...
```

The YubiKey will prompt for your User PIN on the first SSH connection
in a session.

## Signing

### Sign a file

Detached signature (recipient verifies with your public key):

```bash
gpg --detach-sign --armor document.pdf
# produces document.pdf.asc
```

Clear-sign (signature embedded in text -- good for email):

```bash
gpg --clear-sign message.txt
# produces message.txt.asc
```

The YubiKey LED will blink and you will be prompted for your User PIN.

### Verify a signature

```bash
gpg --verify document.pdf.asc document.pdf
```

If you don't have the signer's key:

```bash
gpg --keyserver hkps://keys.openpgp.org --recv-keys <sender-fingerprint>
gpg --verify document.pdf.asc document.pdf
```

> Verification only uses public keys -- no YubiKey needed.

## Encryption

### Encrypt to a recipient

```bash
gpg --recipient recipient@example.com --encrypt --armor document.pdf
# produces document.pdf.asc
```

### Encrypt to yourself (for secure storage)

```bash
gpg --recipient "${KEYID}" --encrypt --armor document.pdf
```

### Encrypt and sign

```bash
gpg --recipient recipient@example.com --encrypt --sign --armor document.pdf
```

### Decrypt

```bash
gpg --decrypt document.pdf.asc > document.pdf
```

The YubiKey will prompt for your User PIN.

## Symmetric encryption (no keys needed)

For quick encryption with just a passphrase (no YubiKey or GPG keys):

```bash
gpg --symmetric --cipher-algo AES256 --armor document.pdf
# prompts for a passphrase

gpg --decrypt document.pdf.asc > document.pdf
```

> No YubiKey needed -- this is purely passphrase-based.

## Git

### Sign commits and tags

With `commit.gpgsign = true` (set above), commits are signed
automatically:

```bash
git commit -m "signed commit"
git tag -s v1.0 -m "signed tag"
```

The YubiKey LED blinks and the PIN prompt appears for each commit.

### Verify commits and tags

```bash
git log --show-signature -1
git tag -v v1.0
```

### One-off unsigned commit (when YubiKey is unavailable)

```bash
git commit --no-gpg-sign -m "unsigned commit"
```

## SSH

### Connect to a remote host

```bash
ssh user@host
```

The first connection in a session triggers the YubiKey PIN prompt.
Subsequent connections reuse the cached PIN until `default-cache-ttl`
expires.

### Clone/push via Git+SSH

```bash
git clone git@github.com:user/repo.git
git push origin main
```

Both use the YubiKey authentication subkey via `gpg-agent`
automatically.

### List available SSH keys

```bash
ssh-add -L
```

---

## Troubleshooting

### YubiKey not detected

```bash
gpg --card-status
# if it fails:
gpgconf --kill all
sudo systemctl restart pcscd
gpg --card-status
```

### PIN prompt not appearing (headless/SSH session)

Make sure `GPG_TTY` is set and pinentry is terminal-based:

```bash
export GPG_TTY="$(tty)"
gpg-connect-agent updatestartuptty /bye
```

If using a GUI session but getting a terminal prompt (or vice versa),
edit `~/.gnupg/gpg-agent.conf`:

```
# For terminal:
pinentry-program /usr/bin/pinentry-curses
# For GNOME:
pinentry-program /usr/bin/pinentry-gnome3
```

Then restart the agent:

```bash
gpgconf --kill gpg-agent
```

### Wrong PIN entered too many times

After 3 wrong User PIN attempts, the card locks.  Unlock with:

```bash
gpg --card-edit
gpg/card> admin
gpg/card> passwd
# select "Reset PIN" and enter the Reset Code
```

After 3 wrong Admin PIN attempts, the OpenPGP applet is permanently
blocked.  You must factory-reset the YubiKey on the safe-image
(see [06-recovery.md](06-recovery.md)).
