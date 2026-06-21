# Design

Architecture, workflows, and security model for the safe-image NixOS live ISO.
See [README.md](README.md) for usage instructions.

## Overview

A single `nix build` invocation inside a thin container produces a bootable
ISO. No mock chroot, no kickstart, no lorax — the entire image is declared in
NixOS modules and assembled by the NixOS ISO image infrastructure.

```
flake.nix + modules/  →  nix build (inside container)  →  ISO  →  USB stick
```

---

## Why NixOS

This project started as a Fedora kickstart + lorax build. The migration to NixOS
solved problems that are structural to the RPM/kickstart approach.

### Reproducibility

| | NixOS | Fedora kickstart |
|-|-------|-----------------|
| Package pins | `flake.lock` — every package pinned by nixpkgs commit hash | DNF resolves latest versions at build time; results vary across Fedora versions and mirror state |
| Same inputs → same ISO | Yes — bit-identical from the same `flake.lock` | No — lorax output varies with host toolchain and package versions |
| Verification | Anyone can rebuild from the same commit and diff | Rebuilds diverge; no way to confirm a signed ISO matches the source |

The GPG signature on the ISO only has value if the ISO is reproducible. With
kickstart, you can sign the output but cannot prove it matches any particular
source state. With NixOS, the same `flake.lock` always produces the same ISO —
the signature over the ISO is also implicitly a signature over the source.

### Build simplicity

Fedora approach required: kickstart → mock chroot → lorax → livemedia-creator →
sometimes a nested QEMU VM for final image assembly. Each step had its own
undeclared dependencies and host-version sensitivities.

NixOS approach: one `nix build` command. The entire image — every package,
config file, service, udev rule — is described in `.nix` files and assembled
in a single deterministic pass.

### Auditable by construction

Kickstart `%post` sections are imperative shell scripts that run at image build
time. Their effect on the final image is opaque without running them.

NixOS modules are declarative: every package, every `/etc` file, every systemd
service is specified as a value. The diff between two commits shows exactly what
changed in the image. There are no hidden install-time side-effects.

### Amnesic live ISO

NixOS `installation-cd-minimal` produces a squashfs image with a tmpfs overlay.
The system is **fully amnesic by design** — no writes reach any disk; everything
lives in RAM and vanishes on reboot. This is a structural property of the image
format, not a configuration option that could accidentally be set wrong.

### No distribution lock-in for the host

The build runs in a container (`nixos/nix`). Any Linux host with Podman or
Docker can build the ISO. The Fedora kickstart approach required mock, lorax,
and rpm — all Fedora-specific tools — making it impractical to build from a
non-Fedora host.

---

## Build workflow

```
┌─ HOST ──────────────────────────────────────────────────────────────┐
│                                                                     │
│  make build                                                         │
│    │                                                                │
│    ├─[signing]─ pick_yubikey  (lib/yubikey-select.sh)               │
│    │              gpg_env_prepare (lib/gpg-env.sh): host env, else  │
│    │                isolated temp GNUPGHOME                         │
│    │              └── smoke-test: gpg --detach-sign (tmp file)      │
│    │                  abort if YubiKey/PIN/touch fail               │
│    │                                                                │
│    ├── podman build  →  builder image (nixos/nix, digest-pinned)    │
│    │                                                                │
│    └── podman run ──────────────────────────────────────────────┐   │
│          mounts:                                                │   │
│            /src  ← project root (read-only)                     │   │
│            /out  ← temp work dir (host: /tmp/safe-live-XXXXXX)  │   │
│            /nix  ← named volume  (Nix store cache)              │   │
│                                                                 │   │
│         ┌─ CONTAINER (nixos/nix) ───────────────────────────┐   │   │
│         │                                                   │   │   │
│         │  nix build .#nixosConfigurations.safe-live        │   │   │
│         │    .config.system.build.isoImage                  │   │   │
│         │      └── pulls packages from cache.nixos.org      │   │   │
│         │            (or Nix store cache volume if warm)    │   │   │
│         │                                                   │   │   │
│         │  cp ISO → /out/                                   │   │   │
│         │  sha256sum → /out/SHA256SUMS                      │   │   │
│         └───────────────────────────────────────────────────┘   │   │
│          └──────────────────────────────────────────────────┘   │   │
│                                                                     │
│    ├─[signing]─ si-sign-outputs.sh --no-smoke                       │
│    │              └── gpg --detach-sign ISO + SHA256SUMS            │
│    │                  (YubiKey on host USB — no container needed)   │
│    │                                                                │
│    └── mv /tmp/safe-live-XXXXXX  →  out/   (atomic promotion)       │
│         only on full success; out/ never left partial               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### What runs where

| Step | Location |
|------|----------|
| YubiKey selection and smoke-test | Host |
| `podman build` (builder image) | Host |
| `nix build` (ISO assembly) | Inside container |
| ISO copy to `out/` | Inside container → host (bind mount) |
| `sha256sum` | Inside container |
| GPG signing | Host (YubiKey on host USB) |
| QEMU test | Host |

### Builder container

| Control | Value |
|---------|-------|
| Base image | `nixos/nix:2.34.6` pinned by SHA256 digest |
| Engine | Podman or Docker (auto-detected) |
| SELinux | `--security-opt label=disable` (Fedora host requirement) |
| Nix sandbox | `sandbox = false` (container seccomp prevents sandbox syscalls) |
| Nix store cache | Named volume `safe-live-nix-store` mounted at `/nix` |
| Source mount | Project root at `/src` read-only (`:ro`; SELinux handled by `--security-opt label=disable`) |
| Work dir | Temp dir at `/out` — receives ISO, SHA256SUMS, and signatures |

---

## Guides

- [Building safely](guides/building-safely.md) — trusted vs untrusted host,
  build workflow, writing and verifying the USB
- [Building on a live OS](guides/building-on-live-os.md) — how to get enough
  disk space when building from a RAM-based live OS (Fedora live, etc.)
- [Debugging build failures](guides/debugging-build-failures.md) — how to
  shell into the builder container, retrieve `nix log` output, and GC the store

---

## Module structure

```
flake.nix
  └── iso.nix  (installation-cd-minimal base)
        ├── modules/base.nix         packages, user, autologin, serial console
        ├── modules/builder.nix      podman + make + git so the live image can
        │                            rebuild safe-image (self-hosting)
        ├── modules/sway.nix         Sway WM, keybindings, fonts, dark mode
        ├── modules/netmode.nix      safe-netmode, nftables, polkit, systemd
        ├── modules/yubikey-gpg.nix  GPG agent, YubiKey udev rules, scdaemon,
        │                            pcscd, safe-yubikey-fetch-pubkey command
        └── modules/docs.nix         safe-docs (glow TUI + ghostwriter), in-image docs
```

Each module is self-contained — it declares packages, services, udev rules, and
config files for its own concern. `iso.nix` composes them.

---

## Boot sequence

```
BIOS/UEFI
  └── GRUB (from installation-cd-minimal)
        └── Linux kernel
              └── systemd
                    ├── nftables.service
                    │     └── load lockdown ruleset  (input/forward/output drop)
                    │
                    ├── udev-trigger-usb.service  (oneshot)
                    │     └── udevadm trigger --subsystem-match=usb
                    │           └── re-apply udev rules to USB devices
                    │               (ensures MODE="0666" on YubiKey in QEMU)
                    │
                    ├── safe-netmode-default-offline.service  (oneshot)
                    │     runs before network-pre.target and NetworkManager
                    │     ├── nftables lockdown table active
                    │     ├── rfkill block all
                    │     ├── ip link set <iface> down  (all non-loopback)
                    │     ├── ip route flush table main
                    │     └── NetworkManager stopped (not started)
                    │
                    └── getty@tty1.service  (autologin as nixos)
                          └── bash loginShellInit
                                └── [[ tty == /dev/tty1 ]] && exec sway
                                      ├── mako          (notification daemon)
                                      ├── i3status bar
                                      └── foot / fuzzel / safe-docs / ...
```

The system is **fully offline before any user process runs**. The offline
lockdown is applied by a systemd oneshot that runs before `network-pre.target`,
which is before NetworkManager, DHCP, or any network service can start.

---

## Network mode state machine

```
                    ┌─────────────────────────┐
                    │       BOOT (offline)    │
                    └────────────┬────────────┘
                                 │ safe-netmode-default-offline.service
                                 ▼
                    ┌──────────────────────────┐
           ┌──────▶│       OFFLINE            |◀───────┐
           │        │  - nftables lockdown     │         │
           │        │  - rfkill block all      │         │
           │        │  - interfaces down       │         │
           │        │  - routes flushed        │         │
           │        │  - NetworkManager off    │         │
           │        └────────────┬─────────────┘         │
           │                     │ safe-netmode online     │
           │                     │ (sudo / polkit)       │
           │                     ▼                       │
           │        ┌──────────────────────────┐         │
           │        │       ONLINE             │         │
           │        │  - nftables: outbound ok │         │
           │        │  - rfkill unblock all    │         │
           │        │  - interfaces up         │         │
           │        │  - NetworkManager on     │         │
           │        └────────────┬─────────────┘         │
           │                     │ safe-netmode offline    │
           └─────────────────────┘ (sudo / polkit)       │
                                                         │
                    Sway keybindings (wrappers add a desktop │
                    notification, then call safe-netmode):   │
                    Mod+Shift+i  →  safe-network-on  ────────┤
                    Mod+Shift+o  →  safe-network-off ────────┘
```

Mode transitions are atomic: the old nftables table is deleted before the new
one is loaded. Both directions (`offline → online`, `online → offline`) delete
and reload tables; the system is never left with overlapping or missing rules.

### nftables rulesets

**Offline (lockdown):**
```
table inet si_net_lockdown {
  chain input   { type filter hook input   priority 0; policy drop;
                  iif lo accept; ct state established,related accept; }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output  { type filter hook output  priority 0; policy drop;
                  oif lo accept; }
}
```

**Online:**
```
table inet si_net_online {
  chain input   { type filter hook input   priority 0; policy drop;
                  iif lo accept; ct state established,related accept; }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output  { type filter hook output  priority 0; policy accept; }
}
```

---

## YubiKey / GPG access

```
YubiKey (USB)
  │
  ├── udev rules (MODE="0666")
  │     SUBSYSTEM=="usb",    ATTRS{idVendor}=="1050"  → MODE="0666"
  │     SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1050"  → MODE="0666"
  │
  ├── pcscd  (services.pcscd.enable = true)
  │     owns the CCID reader; serves PC/SC clients (ykman, opensc, gpg)
  │
  ├── ykman  (yubikey-manager) ──► pcscd
  │
  └── gpg --card-status
        └── gpg-agent
              └── scdaemon  (disable-ccid in /etc/gnupg/scdaemon.conf)
                    routes through libpcsclite → pcscd
```

**Why pcscd is enabled and scdaemon uses PC/SC:**
Running scdaemon's built-in libusb CCID driver and pcscd against the same
reader caused races (`gpg --card-status` flaked on bare metal). Funnelling
both stacks through pcscd via `disable-ccid` gives GPG, ykman, opensc, and
yubico-piv-tool one shared, consistent view of the card. Under QEMU USB
passthrough libccid may still fail to enumerate the reader — in that case
PC/SC-only tools like `ykman list` warn `PC/SC not available`, but GPG
remains usable.

**Why MODE="0666":**
Standard `TAG+="uaccess"` relies on logind propagating access to the console
user. In QEMU, this is timing-sensitive and may not apply before scdaemon
enumerates USB devices. `MODE="0666"` is unconditional and eliminates the race.
This is acceptable for a single-user live image.

---

## Signing workflow

```
HOST (make build — make sign / make sign-test follow the same
      pick_yubikey → gpg_env_prepare → sign path, without the container step)
  │
  ├── pick_yubikey
  │     detect → serial: ykman list
  │     locate → sysfs busnum/devnum (by vendor 1050)
  │     prompt if multiple keys present
  │     export YUBIKEY_SERIAL (no file written)
  │
  ├── gpg_env_prepare 1   (lib/gpg-env.sh — pre-flight, in si-build.sh)
  │     ├── host env, as-is ──── card-status + pubkey + echo-sign smoke
  │     │                         (host config/keyring untouched) → MODE=host
  │     └── else isolated temp GNUPGHOME (disable-ccid, pcsc-shared,
  │           pinentry-curses, keyserver); take over reader; re-test → MODE=temp
  │         abort build (with setup instructions) if neither can sign
  │     exports GPG_ENV_READY / GPG_ENV_MODE / GPG_ENV_KEY / GNUPGHOME
  │
  ├── [nix build inside container]
  │
  └── si-sign-outputs.sh --no-smoke   (actual signing; inherits prepared env)
        for each: ISO, SHA256SUMS
          gpg --batch --yes --local-user <key> --detach-sign --armor <file>
          → <file>.asc
        gpg_env_cleanup on exit (tears down a temp env; host scdaemon respawns)
```

The private key never leaves the YubiKey. YUBIKEY_SERIAL and the prepared
`GPG_ENV_*` / `GNUPGHOME` are passed as environment variables between
si-build.sh and si-sign-outputs.sh — no file on disk, scoped to the build
process lifetime. The signing env is prepared **once** (one PIN + touch for
the pre-flight smoke) and inherited by the signing step.

**Host-first, isolated-temp fallback (`lib/gpg-env.sh`):** a correctly
configured host signs with zero disruption. Only when the host env can't reach
the card or sign — e.g. a fresh Fedora live OS whose `~/.gnupg` lacks
`disable-ccid`, or an empty keyring — does signing fall back to a throwaway
`GNUPGHOME`. Because only one scdaemon can hold the reader at a time (exclusive
PC/SC), the fallback kills the host scdaemon and restarts pcscd to take over
the card, releasing it on cleanup (the host scdaemon respawns on next use).
`make sign-test` runs just this preparation + an echo-sign, for debugging
signing without a build.

---

## Security model

### Trust anchors

| Dependency | Pin | File |
|------------|-----|------|
| nixpkgs | Git commit hash | `flake.lock` |
| Builder image | OCI SHA256 digest | `Dockerfile.builder` `FROM` line |

nixpkgs provides the entire package closure of the live image. Pinning by
commit hash means builds at different times with the same `flake.lock` produce
bit-identical derivations.

### Reproducibility

The ISO is **not committed** to the repository. The source + `flake.lock` are
the artifacts. Anyone who checks out the same commit and runs `make build-no-sign`
gets a bit-identical ISO.

### What we cannot control

- Host kernel and hardware integrity
- Container runtime (Podman/Docker) integrity
- Nix binary cache authenticity (mitigated by nixpkgs trusted-public-keys)
- Supply chain attacks on nixpkgs packages

For maximum assurance, build from a verified live USB on bare metal.

---

## Real hardware vs QEMU

| Concern | QEMU | Real hardware |
|---------|------|---------------|
| YubiKey passthrough | `-device qemu-xhci` + `usb-host` | native USB |
| udev timing | needs udev-trigger-usb service | rules apply normally at boot |
| scdaemon | routes through pcscd via `disable-ccid` (same as bare metal) | routes through pcscd |
| pcscd | runs; libccid may fail to enumerate the QEMU-passed reader → PC/SC tools (ykman) warn but GPG still works | runs and owns the reader normally |
| Display resolution | `virtio-vga` at native resolution | sway uses display native resolution |
| Network interfaces | virtio-net | real NICs; rfkill blocks wireless |

The image boots and runs correctly on both QEMU and real hardware without
changes. The `udev-trigger-usb` service is a no-op on real hardware (udev has
already settled) and harmless.

---

## File classification

| Category | Files | Purpose |
|----------|-------|---------|
| Nix build | `flake.nix`, `flake.lock`, `iso.nix`, `modules/` | Declare the entire image |
| Container build | `Dockerfile.builder`, `si-build.sh` | Provide the Nix build environment |
| Host tooling | `si-sign-outputs.sh`, `si-test.sh`, `Makefile` | Orchestrate build, sign, test |
| Shared helpers | `lib/yubikey-select.sh` | YubiKey selection for host scripts |
| In-image docs | `image/docs/` | Installed at `/etc/safe-live/docs/` |
| In-image scripts | `image/scripts/` | Installed at `/etc/safe-live/scripts/` |
