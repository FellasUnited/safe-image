# Building Safely

How to build safe-image securely, write it to USB, and verify it —
under two scenarios: a trusted host and an untrusted or suspected-compromised host.

## How the build works

The ISO is built by a single `nix build` command inside a minimal container
(`nixos/nix`, digest-pinned in `Dockerfile.builder`). The entire image is
declared in NixOS modules — no imperative install scripts. Any Linux host with
Podman or Docker can build it.

The image is **amnesic**: it runs entirely in RAM (squashfs + tmpfs overlay)
with no writes to disk. All changes within a session vanish on reboot.

The full build pipeline and rationale for choosing NixOS over Fedora kickstart
are in [DESIGN.md](../DESIGN.md).

---

## Scenario A: Trusted host

You trust your OS installation and hardware. Follow the quick start in
`README.md`: `make build-no-sign` or `make build`, then `sha256sum -c out/SHA256SUMS`.

This guide focuses on Scenario B — building when the host cannot be trusted.

---

## Scenario B: Untrusted or suspected-compromised host

You suspect the installed OS is compromised, or you want maximum assurance that
nothing on the host can tamper with the build environment.

### Step 1: Choose a build environment

Boot a clean live OS from USB on either a **different machine** (best) or
**the same machine** (acceptable if you only suspect software compromise).

Two good options:

**Option 1 — A previously verified safe-image (recommended)**
If you already have a trusted safe-image USB: boot it in online mode, clone
the repo, and build. The image is amnesic — nothing from the potentially
compromised host touches the session.

**Option 2 — Fedora Workstation Live**
Podman is available in its repos. Download from a trusted device, verify the
GPG signature and SHA256 against [fedoraproject.org/security](https://fedoraproject.org/security),
write to a **fresh** USB stick (not one previously connected to the suspect host).

> **Boot bare metal, not in a VM.** A compromised host's hypervisor has full
> control over a guest VM. A live USB on bare metal runs its own kernel
> independent of the installed OS.

> **Prefer a different machine.** If you suspect firmware-level compromise
> (UEFI rootkit, hardware implant), boot on a known-clean machine. Firmware
> implants survive OS changes and persist through USB boots on the same hardware.

### Step 2: Install build dependencies

If you booted safe-image (Option 1), **skip this step** — `podman`, `make`,
`git`, `gnupg`, `pinentry-curses`, `yubikey-manager`, and the rest of the
signing stack are already in the image. Go straight to Step 3.

On Fedora Workstation Live (Option 2):

```bash
sudo dnf install -y podman git make
```

To also sign with a YubiKey (`make build`), add the signing stack:

```bash
sudo dnf install -y gnupg2 gnupg2-scdaemon pinentry-curses \
  pcsc-lite pcsc-lite-ccid yubikey-manager
```

### Step 3: Clone and build

```bash
git clone <repo-url> && cd safe-image
make build-no-sign
```

To sign with a YubiKey:

```bash
make build
```

The YubiKey PIN and touch are required once for the smoke test at the start
and once per file at signing. To confirm signing works before a full build,
run `make sign-test` — it tries your host GPG env and, if that can't sign,
falls back to an isolated temporary environment automatically (see the
[README's signing-environment section](../README.md#signing-environment--host-first-isolated-temp-fallback)).

On a fresh live OS the GPG keyring is empty. `make build` / `make sign` /
`make verify` (and inside the image, `safe-yubikey-fetch-pubkey`) all
auto-import the public key from the URL stored on the card. If you have
not configured that URL, set it once with `gpg --card-edit > admin > url`,
or import the pubkey from a file: `gpg --import your-pubkey.asc`. See the
[README's "First-time signing" section](../README.md#first-time-signing--public-key-bootstrap).

To verify the produced signatures (uses the same auto-fetch path):

```bash
make verify
```

If you're on a live OS with limited disk/RAM and the build fails with
"image size exceeds free space", see
[building-on-live-os.md](building-on-live-os.md) for the `CACHE_VOLUME`
recipe and tmpfs/zram options.

### Step 4: Write and verify

See [Writing to USB](#writing-to-usb) below.

---

## Writing to USB

```bash
sudo dd if=out/safe-live-nixos-sway-*.iso of=/dev/sdX \
    bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your target USB device — verify with `lsblk` first.

### Verify the write

```bash
ISO=$(ls out/*.iso | head -1)
ISO_SIZE=$(stat -c%s "$ISO")
sudo dd if=/dev/sdX bs=4M status=none \
    | head -c "${ISO_SIZE}" \
    | sha256sum
```

Compare with:

```bash
cat out/SHA256SUMS
```

---

## Storing the ISO

Keep the `.asc` signatures alongside the ISO — they prove it has not been
modified since signing:

```
out/
├── safe-live-nixos-sway-<label>-x86_64-linux.iso
├── safe-live-nixos-sway-<label>-x86_64-linux.iso.asc
├── SHA256SUMS
└── SHA256SUMS.asc
```

Consider writing to **two USB sticks** stored in separate physical locations.

---

## Bare metal vs VM for building

| | Different machine (USB boot) | Same machine (USB boot) | VM on suspect host |
|-|------------------------------|-------------------------|--------------------|
| Protects against | OS + firmware + hardware compromise | OS compromise only | Nothing |
| Trust level | Highest | High | Low — hypervisor has full control |
| Convenience | Requires a second machine | Requires reboot + USB | Runs alongside normal work |
| When to use | Hardware suspected compromised | Only OS suspected compromised | Host is trusted (Scenario A) |

---

## Checklist

**Scenario A (trusted host):** see `README.md` quick start.

**Scenario B (untrusted host):**
- [ ] Obtain a clean live OS ISO on a separate trusted device
- [ ] Verify its GPG signature and SHA256 checksum
- [ ] Write to a fresh USB stick (not one from the suspect host)
- [ ] Boot bare metal (preferably on a different machine)
- [ ] Install Podman + Git in the live session
- [ ] Clone, build, verify

**After build:**
- [ ] Verify ISO checksum
- [ ] Write to target USB
- [ ] Read back and verify write
- [ ] Store `.asc` signatures alongside the ISO
- [ ] Consider a second USB copy in a separate location
