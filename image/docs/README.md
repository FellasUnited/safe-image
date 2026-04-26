# Safe Live NixOS — Quick Reference

Installed at `/etc/safe-live/docs/` in the live image.

Browse docs: `safe-docs` (terminal TUI) — or `Mod+h` in Sway.

---

## Sway keybindings

Mod = Win/Super key

| Keybinding | Action |
|------------|--------|
| `Mod+Return` | Terminal |
| `Mod+d` | App launcher |
| `Mod+h` | Open docs (safe-docs) |
| `Mod+s` | System status |
| `Mod+Shift+o` | Go offline |
| `Mod+Shift+i` | Go online |
| `Mod+Shift+q` | Close window |
| `Mod+Shift+c` | Reload Sway config |
| `Mod+Shift+e` | Exit Sway |
| `Mod+Arrow` | Focus window left/down/up/right |
| `Mod+Shift+Arrow` | Move window |
| `Mod+1..9` | Switch workspace |
| `Mod+Shift+1..9` | Move window to workspace |
| `Mod+b` / `Mod+v` | Split horizontal / vertical |
| `Mod+f` | Toggle fullscreen |
| `Mod+Shift+Space` | Toggle floating |
| `Mod+Space` | Switch focus tiling/floating |
| `Mod+r` | Resize mode (Arrow keys to resize, Esc to exit) |

---

## Network

```bash
sudo si-netmode offline    # full lockdown
sudo si-netmode online     # allow outbound
si-netmode status          # links, routes, firewall state
safe-status                # full system overview
```

Boots offline. Online mode allows outbound traffic and starts NetworkManager.
Inbound remains default-drop. See [network-modes.md](network-modes.md).

Wi-Fi setup: see [network-modes.md#connecting-to-wi-fi](network-modes.md).

---

## Installing packages at runtime

This image is meant to be **immutable**. If you really need a package right
now, see [runtime-install.md](runtime-install.md) — and then add the package
to the relevant module and rebuild the ISO so it ships in the next boot.

---

## Self-hosting (rebuild the image from inside the image)

The live ISO ships `podman` (with `docker` compat), `make`, `git`, `gnupg`,
and `nix` — everything `make build` needs. This means you can use a
previously verified safe-image USB to build the *next* safe-image, with no
trust dependency on the host's OS or container daemon.

```bash
# 1. Boot the verified live ISO.
# 2. Bring up the network and clone the source.
sudo si-netmode online
git clone <repo-url> && cd safe-image
# 3. Build — same Makefile targets as on a normal host.
make build-no-sign       # or `make build` to sign with your YubiKey
```

On tmpfs-backed live sessions, point the Nix store cache at a mounted
disk first (see the `CACHE_VOLUME` notes in the project README and the
host-side `guides/building-on-live-os.md`).

---

## YubiKey / GPG

```bash
ykman list                   # detect inserted YubiKeys
ykman openpgp info           # OpenPGP applet status
gpg --card-status            # GPG card info

# Fresh boot — pull your public key from the URL stored on the card.
# Needs network: run `sudo si-netmode online` first.
safe-yubikey-fetch-pubkey
```

If `gpg --card-status` fails:

```bash
gpgconf --kill gpg-agent scdaemon
gpg --card-status
```

See [gpg-yubikey.md](gpg-yubikey.md) for common operations.
See [host-setup.md](host-setup.md) to configure a daily workstation (packages, pcscd, udev rules).

---

## Guides

Step-by-step workflows are in [guides/](guides/README.md):

- **First-time setup:** guides 01 → 02 → 03
- **Annual maintenance:** guide 04 (extend subkey expiry)
- **Emergency:** guides 05 → 06 (revoke / recover)
- **System hardening:** guides 07 → 08 (FIDO2 login / LUKS)

> Any operation touching private key material must be performed on this image,
> booted offline.
