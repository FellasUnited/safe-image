# safe-image

Reproducible NixOS live ISO for offline-first security work. The image
boots from a USB stick with all network interfaces disabled and a full
nftables lockdown in place. A desktop toggle lets you go online only when
you choose to.

## What you get

- **Offline-first** — boots with all radios blocked, interfaces down, routes
  flushed, nftables lockdown active. Toggle online/offline from Sway or terminal.
- **YubiKey / smartcard stack** — `gnupg`, `opensc`,
  `yubikey-manager`, `yubico-piv-tool`. pcscd owns the reader; scdaemon
  delegates via PC/SC (`disable-ccid`) so GPG and PC/SC tools share one view.
  Includes `safe-yubikey-fetch-pubkey` for downloading the public key from
  the URL stored on the card after a fresh boot.
- **Sway desktop** — autostarts on TTY1 login; `foot` terminal, `fuzzel`
  launcher, `i3status` bar, `mako` notifications.
- **Browser** — LibreWolf (privacy-hardened Firefox).
- **Editors** — Emacs, Vim, Nano.
- **Guides** — step-by-step YubiKey/GPG lifecycle guides accessible
  via `safe-docs` (`Mod+h` in Sway).
- **Reproducible** — nixpkgs pinned in `flake.lock`; builder image
  pinned by SHA256 digest in `Dockerfile.builder`.

## Prerequisites

A Linux host with:

- **Podman** or **Docker**
- **make** and **Bash**

Optional:

- **YubiKey** — for GPG output signing (`make sign`)

Install on Fedora:

```bash
sudo dnf install podman make
```

For YubiKey signing (`make build` / `make sign`):

```bash
sudo dnf install gnupg2 gnupg2-scdaemon pinentry-curses \
  pcsc-lite pcsc-lite-ccid yubikey-manager
```

## Quick start

```bash
git clone <this-repo> && cd safe-image

# Build the ISO (uses a cached Nix store volume by default)
make build-no-sign

# Smoke-test: boot headless in QEMU, verify offline mode
make test

# Interactive test: boot in a QEMU window (prompts for YubiKey passthrough)
make test-gui

# Sign outputs with YubiKey
make sign

# Verify the resulting *.asc signatures against the YubiKey's signing key
make verify
```

> **First-time signing on a fresh host:** the local GPG keyring is empty,
> so `make build` / `make sign` will try to fetch your public key from the
> URL stored on the card (`gpg --card-edit > admin > url`). If you have not
> set that URL, either set it once, import the pubkey from a file
> (`gpg --import your-pubkey.asc`), or `gpg --recv-keys <fingerprint>` from
> a keyserver.

## Make targets

| Target | Description |
|--------|-------------|
| `make build` | Build ISO + sign outputs with YubiKey |
| `make build-no-sign` | Build ISO, skip signing |
| `make build-no-cache` | Build without the Nix store cache volume |
| `make sign` | Sign existing `out/` artifacts with YubiKey |
| `make sign-test` | Sign a throwaway string to confirm YubiKey signing works (no build) |
| `make verify` | Verify `out/*.asc` signatures against the YubiKey's signing key |
| `make test` | Boot ISO in headless QEMU, verify offline mode |
| `make test-gui` | Boot ISO in a QEMU window for interactive testing |
| `make clean` | Remove `out/` and `result` |
| `make clean-cache` | Remove the Nix store cache (re-prompts). Honors `CACHE_VOLUME` for bind-mount paths. |
| `make clean-all` | Reclaim everything: `out/`, leftover `/tmp` dirs, builder + base container images, cache (re-prompts). Honors `CACHE_VOLUME`. |

**Environment variables:**

```bash
SKIP_SIGN=1 make build      # same as build-no-sign
ENGINE=docker make build    # force Docker instead of Podman
USE_CACHE_VOLUME=0 make build  # disable Nix store caching
GUI=1 ./si-test.sh          # same as make test-gui
SPICE=1 make test-gui       # use spice-app + remote-viewer (clipboard on Fedora)
```

> **Clipboard in test-gui:** the default `gtk` display only syncs clipboard
> when QEMU was compiled with `-display gtk,clipboard=on` support. Fedora's
> QEMU is not. On Fedora, run `SPICE=1 make test-gui` (requires the
> `virt-viewer` package) — clipboard works via the SPICE vdagent channel.

## Build output

```
out/
├── safe-live-nixos-sway-<label>-x86_64-linux.iso      # live ISO
├── safe-live-nixos-sway-<label>-x86_64-linux.iso.asc  # GPG signature (after sign)
├── SHA256SUMS                                         # checksums
└── SHA256SUMS.asc                                     # checksum signature (after sign)
```

The ISO is not committed to the repository. See [Reproducibility](#reproducibility).

## Building securely

The quick start above assumes a trusted host. If you suspect your OS or hardware
is compromised, build from a clean live USB instead — ideally from a previously
verified safe-image booted in online mode, which makes this project self-hosting.
The live ISO ships podman, make, git, gnupg, and nix, so the same `make build`
flow works inside it with no extra dependencies.

Full procedure, bare metal vs VM analysis, and post-build verification checklist:
[guides/building-safely.md](guides/building-safely.md)

## Writing to USB

```bash
sudo dd if=out/safe-live-nixos-sway-*.iso of=/dev/sdX \
    bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your USB device. For full write-back verification see
[guides/building-safely.md](guides/building-safely.md).

## Project layout

```
.
├── flake.nix               # Nix flake entry point
├── flake.lock              # Pinned nixpkgs revision (commit this)
├── iso.nix                 # Top-level NixOS ISO configuration
├── modules/
│   ├── base.nix            # Base packages, user, autologin, serial console
│   ├── builder.nix         # Podman + make + git so the image can rebuild itself
│   ├── sway.nix            # Sway WM, keybindings, fonts, dark mode
│   ├── netmode.nix         # safe-netmode, nftables, polkit, systemd service
│   ├── yubikey-gpg.nix     # GPG, YubiKey udev rules, scdaemon PC/SC config
│   └── docs.nix            # safe-docs command, in-image documentation
├── image/
│   ├── docs/               # Installed into ISO at /etc/safe-live/docs/
│   │   ├── README.md       # Primary in-image guide
│   │   ├── network-modes.md
│   │   ├── gpg-yubikey.md
│   │   ├── host-setup.md
│   │   ├── runtime-install.md
│   │   └── guides/         # Full YubiKey lifecycle guides (01-08)
│   └── scripts/            # Installed into ISO at /etc/safe-live/scripts/
├── lib/
│   ├── yubikey-select.sh        # YubiKey selection helper (sourced)
│   ├── yubikey-fetch-pubkey.sh  # Card-URL pubkey fetch (sourced + shipped in image)
│   └── gpg-env.sh               # Signing env: host first, isolated temp fallback (sourced)
├── Dockerfile.builder      # nixos/nix builder image (digest-pinned)
├── si-build.sh             # Build orchestration (Podman/Docker)
├── si-sign-outputs.sh      # Host-side YubiKey GPG signing
├── si-sign-test.sh         # Sign a throwaway string to confirm signing works
├── si-verify.sh            # Verify out/*.asc against the YubiKey signing key
├── si-test.sh              # QEMU smoke-test and GUI boot
└── Makefile
```

## Network mode

The live image boots in **offline mode** by default:

- All radios blocked via `rfkill`.
- All non-loopback interfaces brought down.
- IPv4/IPv6 routes flushed.
- nftables lockdown: input/forward/output drop (loopback excepted).
- NetworkManager stopped.

Toggle from Sway (Mod = Win/Super key):

| Keybinding | Action |
|------------|--------|
| `Mod+Return` | Terminal |
| `Mod+d` | App launcher |
| `Mod+h` | Open docs |
| `Mod+s` | System status |
| `Mod+Shift+o` | Go offline |
| `Mod+Shift+i` | Go online |
| `Mod+Arrow` / `Mod+Shift+Arrow` | Focus / move window |
| `Mod+1..9` / `Mod+Shift+1..9` | Switch / move to workspace |
| `Mod+f` / `Mod+r` | Fullscreen / resize mode |

Or from the terminal:

```bash
sudo safe-netmode offline
sudo safe-netmode online
safe-netmode status
```

## YubiKey & GPG guides

The live image includes step-by-step guides at `/etc/safe-live/docs/guides/`:

| Guide | Topic |
|-------|-------|
| `01-generate-keys.md` | Ed25519 master key + subkeys |
| `02-yubikey-setup.md` | Move subkeys to card, change PINs |
| `03-daily-use.md` | Sign, encrypt, Git, SSH |
| `04-extend-expiry.md` | Renew subkeys |
| `05-revoke-keys.md` | Revoke master or subkeys |
| `06-recovery.md` | Backup, restore, factory reset |
| `07-linux-login.md` | FIDO2 login/sudo/screen unlock |
| `08-luks-unlock.md` | FIDO2 LUKS unlock at boot |

Open with `safe-docs` or `Mod+h` in Sway.

## Signing

```bash
make sign-test      # confirm signing works (signs a throwaway string)
make sign           # sign existing out/ artifacts
make verify         # verify the resulting *.asc files
```

Requires a YubiKey with a GPG signing subkey. The scripts detect connected
YubiKeys, ensure the public key is in the local keyring (auto-fetching it
from the URL stored on the card if needed — see below), run a smoke-test
signature, then sign the ISO and `SHA256SUMS` with detached `.asc`
signatures. YubiKey touch and PIN are required.

### Signing environment — host first, isolated temp fallback

Signing, `make sign-test`, and `make verify` all prepare a GPG environment via
`lib/gpg-env.sh`:

1. **Host env, as-is** — if your host GPG already reaches the card and can sign
   (the normal case on a configured machine), it is used unchanged. Your
   `~/.gnupg` config and keyring are never modified.
2. **Isolated temp `GNUPGHOME` fallback** — if the host env can't sign (typical
   on a fresh Fedora live OS), a throwaway home is created with the right
   `scdaemon.conf` (`disable-ccid`, `pcsc-shared`), a `pinentry-curses` agent,
   and a reliable keyserver. Because only one scdaemon can hold the reader, the
   fallback restarts pcscd and takes over the card, then releases it on exit
   (the host scdaemon respawns on its next use). This path runs **only** when
   the host env already could not sign.

If neither works, the command aborts and prints exact setup steps (install the
scdaemon/pinentry stack, add `disable-ccid`, restart pcscd, get the public key
into the keyring). Run `make sign-test` to debug signing without a full build.

### First-time signing — public key bootstrap

The YubiKey holds only the **private** key. GPG also needs the public half
in the local keyring before it can sign. `make build` / `make sign` /
`make verify` (and the in-image `safe-yubikey-fetch-pubkey` command) all
invoke `gpg --card-edit > fetch`, which tries two paths in order:

1. **Card URL** — set with `gpg --card-edit > admin > url`. Used if present.
2. **Keyserver lookup by fingerprint** — fallback when no URL is on the card.
   Uses whichever keyserver is configured in `dirmngr.conf` (the live image
   ships `keyserver hkps://keyserver.ubuntu.com:443`).

URL-first is the right order: a URL you control (your own server, a
GitHub raw URL, etc.) is more durable than a public keyserver that may
hold stale data, go down, or strip identity packets. Set one with
`gpg --card-edit > admin > url <https-url-to-pubkey>` once and the
keyserver becomes a fallback rather than the primary path. Note that
`ykman` cannot set this field — `gpg --card-edit > admin > url` is the
only supported way. See
[guides/02-yubikey-setup.md](image/docs/guides/02-yubikey-setup.md) for
the full step.

If your key was ever uploaded to the configured keyserver, fetch
typically succeeds even without a URL on the card. If both attempts fail:

```bash
gpg --import /path/to/your-pubkey.asc                          # from a file
gpg --keyserver hkps://keyserver.ubuntu.com:443 --recv-keys <fingerprint>   # try another server
```

### Verifying from another machine

```bash
gpg --keyserver hkps://keyserver.ubuntu.com:443 --recv-keys <fingerprint>
gpg --verify out/safe-live-nixos-sway-*.iso.asc
gpg --verify out/SHA256SUMS.asc
```

## Reproducibility

The ISO is **not committed** to the repository. Instead, the inputs are
pinned so that anyone can reproduce a bit-identical ISO from the same source:

| Anchor | Mechanism | File |
|--------|-----------|------|
| nixpkgs revision | Git commit hash | `flake.lock` |
| Builder image | OCI SHA256 digest | `Dockerfile.builder` `FROM` line |

`flake.lock` **must be committed**. It is the reproducibility anchor — the
same `flake.lock` produces the same package closure, which produces the same
ISO. The GPG signatures prove that a specific key signed a build from a
specific source state.

For distribution, publish the ISO + `.asc` signatures as a release artifact.
Users verify the signature and, if they want, independently reproduce the ISO
from the same commit to confirm it matches.

## Maintaining this repo

### Adding or changing packages

Edit the relevant module in `modules/` and rebuild:

```bash
make build-no-sign
make test-gui
```

NixOS modules are declarative — add a package to `environment.systemPackages`
in the appropriate `.nix` file and it appears in the image.

### Updating nixpkgs

```bash
nix flake update        # rewrites flake.lock to latest nixpkgs
git add flake.lock
git commit -m "chore: bump nixpkgs to <new-rev>"
make build-no-sign
```

Verify the build and test before committing. The new `flake.lock` is the new
reproducibility anchor.

### Updating the builder image

The builder image digest is pinned in `Dockerfile.builder`. To update:

1. Find the new digest for `nixos/nix` on Docker Hub.
2. Update the `FROM nixos/nix@sha256:...` line in `Dockerfile.builder`.
3. Rebuild and test.
4. Commit `Dockerfile.builder`.

### Commit discipline

- Commit `flake.lock` whenever you run `nix flake update`.
- Never commit `out/` — the ISO and signatures are build artifacts.
- Commit `.asc` signatures only if you want them in the repo history
  (typically attach them to a GitHub Release instead).

### Testing changes without a full build

Check Nix syntax: `nix flake check` (if you have Nix installed on the host).
Only the container build produces the final ISO.

### NixOS module idioms used here

- `pkgs.writeShellApplication` — creates a checked shell script as a
  Nix package, with `runtimeInputs` automatically added to PATH.
- `pkgs.makeDesktopItem` — generates a `.desktop` file package.
- `environment.etc."path".text` — writes a file into `/etc/` in the image.
- `lib.mkForce` — overrides a value set by an imported NixOS module.

## Architecture

See [DESIGN.md](DESIGN.md) for the build pipeline, boot sequence, security model, and
the rationale for choosing NixOS over a Fedora kickstart approach.

## License

See [LICENSE](LICENSE).
