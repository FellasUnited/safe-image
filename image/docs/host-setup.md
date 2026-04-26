# Host Setup for YubiKey + GPG

How to configure a daily workstation or laptop to use a YubiKey for GPG
signing, encryption, and SSH — including automatic re-detection after removal,
reinsertion, and KVM switches.

After completing this guide, follow [guides/03-daily-use.md](guides/03-daily-use.md)
to import your public key, configure SSH, and set up Git signing.

---

## 1. Install packages

### Fedora (standard — DNF)

```bash
sudo dnf install -y \
  gnupg2 \
  gnupg2-scdaemon \
  pinentry-gnome3 \
  pinentry-curses \
  pcsc-lite \
  pcsc-lite-ccid \
  pcsc-tools \
  yubikey-manager \
  yubikey-personalization \
  yubico-piv-tool \
  opensc
```

### Fedora Atomic (Silverblue, Kinoite, Sericea — rpm-ostree)

The base image is immutable. Layer the packages and reboot:

```bash
sudo rpm-ostree install \
  gnupg2 \
  pinentry-gnome3 \
  pinentry-curses \
  pcsc-lite \
  pcsc-lite-ccid \
  yubikey-manager \
  yubikey-personalization \
  yubico-piv-tool \
  opensc

sudo systemctl reboot
```

> **Do not use Toolbox/Distrobox for pcscd or gpg-agent.** These daemons
> must run on the host to share the smartcard across all applications (SSH,
> Git, browsers). Containerised agents only serve processes inside the
> container.

### Debian / Ubuntu

```bash
sudo apt install -y \
  gnupg2 \
  pinentry-gnome3 \
  pinentry-curses \
  pcscd \
  pcsc-tools \
  libccid \
  yubikey-manager \
  yubikey-personalization \
  yubico-piv-tool \
  opensc \
  scdaemon
```

---

## 2. Enable pcscd

pcscd is the PC/SC daemon that manages smartcard readers. On the host it
provides multiplexed access — multiple applications (gpg-agent, opensc, ssh)
can share the card without conflicts.

```bash
sudo systemctl enable --now pcscd.service
```

Verify it is running:

```bash
sudo systemctl status pcscd.service
```

Test detection:

```bash
ykman list          # should show your YubiKey model and serial
gpg --card-status   # should show OpenPGP card info
```

---

## 3. Configure GPG

### ~/.gnupg directory permissions

```bash
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg
```

GnuPG refuses to run if the directory has loose permissions.

### ~/.gnupg/gpg.conf

```bash
cat > ~/.gnupg/gpg.conf << 'EOF'
use-agent
keyid-format 0xlong
with-fingerprint
charset utf-8
no-greeting
personal-digest-preferences SHA512 SHA384 SHA256
personal-cipher-preferences AES256 AES192 AES
cert-digest-algo SHA512
EOF
```

### ~/.gnupg/scdaemon.conf

On the host, scdaemon delegates to pcscd (unlike the live image where
pcscd is disabled). `disable-ccid` prevents scdaemon's built-in CCID
driver from racing against pcscd for the USB interface:

```bash
cat > ~/.gnupg/scdaemon.conf << 'EOF'
# Delegate smartcard access to pcscd (standard for desktop hosts).
disable-ccid

# Fedora: explicit path to libpcsclite (optional; scdaemon finds it
# automatically on most distros, but required if it cannot locate the lib).
# pcsc-driver /usr/lib64/libpcsclite.so.1

# Release the card connection after 5 seconds of inactivity.
# This lets pcscd detect a new card quickly after removal/reinsertion.
card-timeout 5
EOF
```

### ~/.gnupg/gpg-agent.conf

See [guides/03-daily-use.md](guides/03-daily-use.md) — it covers the full
gpg-agent.conf including SSH support, cache TTL, and pinentry selection.

---

## 4. Shell profile

The GPG environment and YubiKey touch notifications are set up together in
`~/.bashrc.d/gpg-yubikey.bash` (see section 8a-ii). If you prefer a single
`~/.bashrc`, add the following directly to it instead:

```bash
export GPG_TTY="$(tty)"
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
if command -v gpgconf >/dev/null 2>&1; then
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
fi
```

Apply immediately:

```bash
source ~/.bashrc
```

Disable the default ssh-agent so it does not conflict:

```bash
systemctl --user disable --now ssh-agent.service 2>/dev/null || true
```

---

## 5. Udev rules for automatic re-detection

By default, removing and reinserting a YubiKey — or switching a KVM — leaves
pcscd and scdaemon in a stale state. The next `gpg` operation fails until
you manually restart them.

The fix is two udev rules:

```bash
sudo tee /etc/udev/rules.d/69-yubikey.rules << 'EOF'
# Kill scdaemon when a YubiKey is removed so it re-initialises on next use.
ACTION=="remove", SUBSYSTEM=="usb", ATTRS{idVendor}=="1050", \
  RUN+="/usr/bin/pkill -x scdaemon"

# Restart pcscd when a YubiKey is inserted for clean re-enumeration.
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="1050", \
  RUN+="/usr/bin/systemctl --no-block restart pcscd.service"
EOF

sudo udevadm control --reload-rules
```

After this, inserting or removing any YubiKey automatically:
- Kills scdaemon (it restarts on next GPG operation, finding the new card)
- Restarts pcscd (clean enumeration of the newly inserted key)

---

## 6. The KVM switch problem

A KVM (keyboard-video-mouse) switch that also passes USB through to the
active machine causes the YubiKey to appear as if it was unplugged and
replugged each time you switch hosts.

**What happens without the udev rules:**

1. You switch away — USB disconnect — pcscd loses the reader.
2. You switch back — USB reconnect — pcscd may not re-detect the reader.
3. scdaemon has a stale cached connection from before the switch.
4. `gpg --card-status` fails.

**What happens with the udev rules:**

1. Switch away → remove rule fires → scdaemon is killed.
2. Switch back → add rule fires → pcscd restarts, re-enumerates the key.
3. Next GPG operation → scdaemon starts fresh → finds the card via pcscd.
4. `gpg --card-status` succeeds.

**If the KVM does not pass USB through at all** (separate USB ports per host):
the YubiKey stays connected to its host and is unaffected by switching. No
special configuration needed in that case.

**Manual fix** (without udev rules, or when things get stuck):

```bash
gpgconf --kill scdaemon
sudo systemctl restart pcscd.service
gpg --card-status
```

---

## 7. Multiple YubiKeys

If you own more than one YubiKey (e.g., a primary and a backup):

- Each YubiKey has its own serial number.
- pcscd and scdaemon work with whichever key is currently inserted.
- GPG uses the key whose serial matches the stubs in `~/.gnupg/`.

To switch keys:

1. Remove the current key — the remove udev rule kills scdaemon.
2. Insert the other key — the add udev rule restarts pcscd.
3. Run `gpg --card-status` — scdaemon reinitialises against the new card.

If you load the same subkeys onto multiple YubiKeys (see
[guides/06-recovery.md](guides/06-recovery.md)), GPG will use whichever
key is inserted transparently.

To check which key is currently active:

```bash
ykman list
gpg --card-status | grep "Serial number"
```

---

## 8. YubiKey operation notifications

GnuPG has no single hook that fires before every card operation. Two complementary
mechanisms cover all cases:

| Scenario | Mechanism | How it works |
|----------|-----------|--------------|
| Touch required (PIN cached) | `yubikey-touch-detector` | Daemon sends an assuan `LEARN` probe after the key stub is opened; if the card is busy waiting for touch, `LEARN` blocks and `GPG_1` is emitted |
| Touch required (PIN not cached) | Pinentry wrapper | After PIN entry, wrapper re-opens the key stubs so yubikey-touch-detector fires a fresh `LEARN` probe at the right moment |

Both work together. Without the wrapper, yubikey-touch-detector's probe fires
200 ms after the key stub is first opened — before the card starts the PKSIGN
operation — and no notification is emitted on first use. The wrapper closes
that gap.

### 8a. yubikey-touch-detector (touch notifications)

`yubikey-touch-detector` is not packaged for Fedora. Two install options:

**Option A — Nix (digest-pinned, reproducible)**

Pins to the same nixpkgs revision used by this project; Nix verifies all
content by store hash:

```bash
NIXPKGS_REV=$(nix flake metadata ~/code/safe-image --json \
  | python3 -c "import sys,json; d=json.load(sys.stdin); \
    print(d['locks']['nodes']['nixpkgs']['locked']['rev'])")

echo "Installing from nixpkgs rev: ${NIXPKGS_REV}"
nix profile install "github:NixOS/nixpkgs/${NIXPKGS_REV}#yubikey-touch-detector"
```

The Nix package ships both a service and socket unit. Copy them and enable:

```bash
PKG_ROOT=$(dirname "$(dirname "$(readlink -f "$(which yubikey-touch-detector)")")")
mkdir -p ~/.config/systemd/user
cp "$PKG_ROOT"/lib/systemd/user/yubikey-touch-detector.{service,socket} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now yubikey-touch-detector.socket
```

**Option B — go install (no Nix required)**

Requires Go (`sudo dnf install golang`) and `libgpgme-devel` (`sudo dnf install gpgme-devel`):

```bash
go install github.com/maximbaz/yubikey-touch-detector@latest
```

The binary lands in `~/go/bin/`. Write the service and socket units manually:

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/yubikey-touch-detector.service << 'EOF'
[Unit]
Description=Detects when your YubiKey is waiting for a touch
Requires=yubikey-touch-detector.socket

[Service]
ExecStart=%h/go/bin/yubikey-touch-detector
EnvironmentFile=-%E/yubikey-touch-detector/service.conf

[Install]
Also=yubikey-touch-detector.socket
WantedBy=default.target
EOF

cat > ~/.config/systemd/user/yubikey-touch-detector.socket << 'EOF'
[Unit]
Description=Unix socket activation for YubiKey touch detector service

[Socket]
ListenStream=%t/yubikey-touch-detector.socket
RemoveOnStop=yes

[Install]
WantedBy=sockets.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now yubikey-touch-detector.socket
```

> `go install` fetches the latest release without digest verification. Prefer
> Option A when reproducibility or supply-chain integrity matters.

---

**Configure notifications** via `$XDG_CONFIG_HOME/yubikey-touch-detector/service.conf`:

```bash
mkdir -p ~/.config/yubikey-touch-detector
cat > ~/.config/yubikey-touch-detector/service.conf << 'EOF'
# enable debug logging
YUBIKEY_TOUCH_DETECTOR_VERBOSE=false

# show desktop notifications using libnotify
YUBIKEY_TOUCH_DETECTOR_LIBNOTIFY=true

# print notifications to stdout (captured in journal: journalctl --user -u yubikey-touch-detector)
YUBIKEY_TOUCH_DETECTOR_STDOUT=true

# disable unix socket notifier
YUBIKEY_TOUCH_DETECTOR_NOSOCKET=false
EOF
```

Restart the service to apply:

```bash
systemctl --user restart yubikey-touch-detector.service
```

Verify it is running:

```bash
systemctl --user status yubikey-touch-detector.service
ls "$XDG_RUNTIME_DIR/yubikey-touch-detector.socket"
```

From this point on, any time an operation is waiting for a touch (LED blinking),
a desktop notification appears: **"YubiKey is waiting for touch"**.

### 8a-ii. CLI notifications (same terminal)

Desktop notifications appear regardless of which terminal triggered the
operation. To also print a message in the triggering terminal, place the
following in `~/.bashrc.d/gpg-yubikey.bash` (sourced automatically if
`~/.bashrc` contains the standard `~/.bashrc.d/` loader). It requires `socat`
(`sudo dnf install socat`).

The file should also contain the GPG environment setup so the whole YubiKey
configuration lives in one place:

```bash
mkdir -p ~/.bashrc.d
cat > ~/.bashrc.d/gpg-yubikey.bash << 'EOF'
# GPG agent and YubiKey touch notifications

# Restore gpg-agent + YubiKey to a working state for the current terminal.
# Called automatically at shell startup; safe to call manually any time things
# break — after killing the agent, a KVM switch, card removal, or pcscd hiccup.
gpg-restore() {
    gpgconf --kill scdaemon 2>/dev/null

    if ! gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1; then
        gpgconf --kill gpg-agent 2>/dev/null
        gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
    fi

    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"

    # Update TTY record for pinentry-notify (gpg-agent has no controlling
    # terminal so it cannot read $GPG_TTY directly).
    printf '%s' "$GPG_TTY" > "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ytd-active-tty"

    if gpg --card-status >/dev/null 2>&1; then
        echo "🟢 GPG + YubiKey: OK"
    else
        echo "❌ Card not accessible — if the above didn't help, try:"
        echo "   sudo systemctl restart pcscd.service && gpg-restore"
    fi
}

export GPG_TTY="$(tty)"
gpg-restore >/dev/null  # silent on normal startup; errors still propagate

# yubikey-touch-detector: notify current terminal when touch is needed
#
# GPG_1 is emitted only when the card is blocked on PKSIGN waiting for touch
# (the detector sends LEARN via assuan; LEARN blocks on a busy card and the
# 400 ms timer fires → GPG_1). The pinentry wrapper re-opens the key stubs
# after PIN entry so the detector re-runs at the right moment. By the time
# GPG_1 arrives here, pinentry has already exited — no pinentry handling needed.
# if tty -s && command -v socat >/dev/null 2>&1; then
#     _ytd_socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/yubikey-touch-detector.socket"
#     _ytd_warn=$(tput setaf 3 2>/dev/null)
#     _ytd_ok=$(tput bold 2>/dev/null)
#     _ytd_rst=$(tput sgr0 2>/dev/null)
#     _ytd_cmds='gpg2?|gpgsm|gpgtar|ssh|scp|sftp|rsync|git|pass|age|sops'
#     (socat -u UNIX-CONNECT:"$_ytd_socket",retry=15,interval=1 - 2>/dev/null | \
#         while IFS= read -r -d '' -n5 msg; do
#             case "$msg" in
#                 *_1)
#                     _ytd_mine=0
#                     _ytd_i=0
#                     while [ "$_ytd_i" -lt 10 ]; do
#                         if ps -t "${GPG_TTY#/dev/}" -o comm= 2>/dev/null \
#                                 | grep -qE "^($_ytd_cmds)$"; then
#                             _ytd_mine=1
#                             break
#                         fi
#                         sleep 0.1
#                         _ytd_i=$((_ytd_i + 1))
#                     done
#                     [ "$_ytd_mine" = 1 ] || continue
#                     printf '\r%s🛡️  Touch YubiKey now%s\n' \
#                         "$_ytd_warn" "$_ytd_rst" >/dev/tty 2>/dev/null ;;
#                 *_0)
#                     if [ "${_ytd_mine:-0}" = 1 ]; then
#                         _ytd_mine=0
#                         printf '\r%s🟢 YubiKey: done%s\n' \
#                             "$_ytd_ok" "$_ytd_rst" >/dev/tty 2>/dev/null
#                     fi ;;
#             esac
#         done) &
#     disown %% 2>/dev/null
#     unset _ytd_socket _ytd_warn _ytd_ok _ytd_rst _ytd_cmds
# fi
EOF
```

If your `~/.bashrc` does not already source `~/.bashrc.d/`, add:

```bash
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        [ -f "$rc" ] && . "$rc"
    done
    unset rc
fi
```

Key points:
- `socat -u` — unidirectional (socket → stdout only); without `-u`, socat also reads
  stdin and gets **SIGTTIN** in the background, silently stopping the process.
- `_ytd_cmds` — regex of all commands that route through gpg-agent. Extend as needed.
- `GPG_TTY` — set at shell startup via `export GPG_TTY="$(tty)"`. The ownership check
  uses `ps -t "${GPG_TTY#/dev/}"` to confirm a triggering command is running on *this*
  terminal. All other terminals skip the event silently.
- Ownership poll — waits up to 1 s for the triggering process to appear (there is a
  brief window between when the key stub is opened and when the process is visible in
  `ps`).
- No pinentry handling — `GPG_1` is emitted only when the card is actually blocking on
  touch, never during PIN entry. The pinentry wrapper (section 8b) ensures a fresh
  `GPG_1` fires after pinentry exits, so by the time this code runs, pinentry is gone.
- `_ytd_mine` — tracks whether this terminal showed a start notification so the done
  message pairs correctly after the triggering process exits.
- `tput setaf`/`sgr0` — reads terminal capabilities at runtime; no hardcoded escapes.
- Socket messages are fixed 5 bytes: `GPG_1`/`GPG_0` (gpg), `U2F_1`/`U2F_0`
  (FIDO2), `MAC_1`/`MAC_0` (HMAC-secret).

### 8b. Pinentry wrapper (re-triggering touch detection after PIN entry)

yubikey-touch-detector fires its `LEARN` probe 200 ms after a shadowed key
stub is opened. On first use (PIN not cached), the card has not started the
PKSIGN operation at that point — pinentry is still running — so `LEARN`
completes instantly and no `GPG_1` is emitted. On subsequent uses (PIN
cached), PKSIGN starts immediately and `LEARN` blocks on the card, so `GPG_1`
fires correctly.

The fix is a pinentry wrapper that re-opens the key stubs after PIN entry.
This fires a fresh inotify `InOpen` event, triggering a new `LEARN` probe at
the correct moment — PKSIGN has just reached the card and is waiting for touch.

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/pinentry-notify << 'EOF'
#!/usr/bin/env bash
# Wrapper around pinentry-curses that re-triggers yubikey-touch-detector after
# PIN entry, so touch notifications fire on first use (PIN not cached).
#
# yubikey-touch-detector watches private-keys-v1.d stubs via inotify InOpen.
# When gpg opens a stub, it sleeps 200 ms then sends AssuanSend("LEARN").
# With PIN not cached the card isn't yet processing PKSIGN at 200 ms, so
# LEARN returns instantly and GPG_1 is never emitted. Re-opening the stubs
# here starts a fresh cycle right when PKSIGN is about to reach the card.

_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

_tty=$(cat "${_dir}/ytd-active-tty" 2>/dev/null)
if [ -w "${_tty:-}" ]; then
    printf '🔐 YubiKey: PIN required\n' > "$_tty"
fi

/usr/bin/pinentry-curses "$@"
_ret=$?
rm -f "${_active}"

# Re-trigger: sleep 100 ms (gpg-agent forwarding PIN to scdaemon), then open
# the shadowed key stubs so yubikey-touch-detector fires a new LEARN probe.
sleep 0.1
_keys="${GNUPGHOME:-$HOME/.gnupg}/private-keys-v1.d"
if [ -d "$_keys" ]; then
    for _f in "$_keys"/*.key; do
        [ -f "$_f" ] && grep -qlF 'shadowed-private-key' "$_f" \
            && cat "$_f" >/dev/null 2>&1
    done
fi
unset _dir _active _keys _f

exit "${_ret}"
EOF
chmod +x ~/.local/bin/pinentry-notify
```

Notes on the stub files: they contain only a card serial number and slot
reference (`OPENPGP.1`, etc.) — no private key material. The real private key
never leaves the YubiKey. Reading them is safe.

`private-keys-v1.d` is the standard key store directory for GnuPG 2.1+
(present on all current distributions). The wrapper guards against its absence
with `[ -d "$_keys" ]`.

Common pinentry programs on Fedora:

```
/usr/bin/pinentry-curses     # terminal (ncurses) — used by the wrapper above
/usr/bin/pinentry-gnome3     # GNOME / GTK
/usr/bin/pinentry-qt         # KDE / Qt
/usr/bin/pinentry-tty        # plain tty, no curses
```

To use a different pinentry program, change the `/usr/bin/pinentry-curses`
line in the wrapper.

Wire it up in `~/.gnupg/gpg-agent.conf`:

```bash
grep -v '^pinentry-program' ~/.gnupg/gpg-agent.conf > /tmp/gac \
    && mv /tmp/gac ~/.gnupg/gpg-agent.conf
echo 'pinentry-program /home/gg/.local/bin/pinentry-notify' >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent
```

> Replace `/home/gg` with your actual home directory, or use `$HOME` if your
> shell expands it — gpg-agent reads the value literally, so tilde (`~`) is
> not expanded.

---

## 9. Verify everything works

```bash
# YubiKey detected
ykman list

# OpenPGP applet accessible
ykman openpgp info

# GPG card status (shows key fingerprints, touch policy, PIN retries)
gpg --card-status

# SSH key available via gpg-agent
ssh-add -L
```

If `gpg --card-status` fails, run the manual fix in section 6 above (KVM / stale state).

Continue with [guides/03-daily-use.md](guides/03-daily-use.md) to import
your public key, configure SSH authorized keys, and set up Git commit signing.
