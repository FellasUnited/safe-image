# Building on a live OS

## The problem

On a Fedora live OS, Podman stores everything — the named Nix store volume
and the container's writable layer — under `~/.local/share/containers/storage/`,
which lives on the root overlay filesystem.  That filesystem is a tmpfs whose
capacity equals **RAM + swap**.

xorriso determines available space with `statvfs()` on the ISO output path,
which is inside the Nix store volume (i.e., on that tmpfs).  With only the
default zram (50% of RAM, capped at 4 GiB), `statvfs()` returns ~678 MB free
and the build fails:

```
xorriso : FAILURE : Image size 1321920s exceeds free space on media 347256s
```

The build writes roughly this much to that tmpfs:

| Artifact | Size |
|---|---|
| Nix packages | ~8–12 GB |
| squashfs image (written to Nix store) | ~3–5 GB |
| ISO output (written to Nix store) | ~2.5 GB |
| **Total** | **~14–20 GB** |

The fix is to mount a dedicated tmpfs that bypasses the root overlay's size
cap.  On low-RAM machines, zram swap may also be needed to back it.

## Option 1 — dedicated tmpfs backed by zram (preferred, no disk needed)

**Mount a dedicated tmpfs.**  The Fedora live root overlay is itself a tmpfs
mounted at boot with a fixed `size=` parameter; `statvfs()` reports free space
relative to that cap, not total RAM.  A fresh tmpfs mount at a new path
bypasses the cap entirely.  The `size=32G` is a limit, not a reservation — the
kernel only allocates pages as data is written, so the mount succeeds even if
less than 32 GB is currently free:

```sh
sudo mkdir -p /mnt/nix-store
sudo mount -t tmpfs -o size=32G,mode=0755,uid=$(id -u),gid=$(id -g) tmpfs /mnt/nix-store
```

Then run the build, pointing the Nix store at the new tmpfs:

```sh
CACHE_VOLUME=/mnt/nix-store make build
```

Everything stays in memory — `/mnt/nix-store` is a tmpfs backed by RAM +
zram, not a disk.  The build runs entirely inside the container as usual.

**If RAM < 32 GB, also add zram** so the tmpfs has enough backing store to
hold the full build.  If RAM is already ≥ 32 GB this step can be skipped:

```sh
# Check current RAM and zram
free -h && zramctl

# Add zram only if RAM alone is below the 32 GB target
RAM_MB=$(awk '/MemTotal/ { print int($2/1024) }' /proc/meminfo)
ZRAM_MB=$(( RAM_MB < 32768 ? 32768 - RAM_MB : 0 ))

if (( ZRAM_MB > 0 )); then
  DEV=$(sudo zramctl --find --size "${ZRAM_MB}M" --algorithm lzo-rle)
  sudo mkswap "$DEV"
  sudo swapon "$DEV"
else
  echo "RAM (${RAM_MB} MB) already meets the 32 GB target; skipping zram."
fi
```

## Option 2 — add a swap file on disk

```sh
sudo mount /dev/sdb1 /mnt/data
sudo fallocate -l 20G /mnt/data/swapfile
sudo chmod 600 /mnt/data/swapfile
sudo mkswap /mnt/data/swapfile
sudo swapon /mnt/data/swapfile
```

Then run the build normally:

```sh
make build
```

## Option 3 — store the Nix volume on disk

Moves the Nix store volume to a real disk so it no longer consumes tmpfs.
The build still runs entirely inside the container.  Requires ≥ 25 GB free.

```sh
sudo mount /dev/sdb1 /mnt/data
CACHE_VOLUME=/mnt/data/nix-store make build
```

`si-build.sh` creates the directory automatically and uses a bind mount.

## Signing on the live OS

`make build` signs the ISO with a YubiKey, and a fresh live `~/.gnupg` often
can't reach the card out of the box (scdaemon fights pcscd for the reader, the
keyring has no public key, and the agent uses a graphical pinentry). You no
longer need to fix this by hand.

Run the signing smoke test first:

```sh
make sign-test
```

It tries your host GPG env as-is, and if that can't sign it automatically falls
back to an **isolated temporary `GNUPGHOME`** configured correctly
(`disable-ccid`, `pcsc-shared`, `pinentry-curses`, a reachable keyserver). That
fallback restarts pcscd and takes over the reader, then releases it on exit —
your host `~/.gnupg` is never modified. `make build` and `make verify` use the
same logic, so once `make sign-test` passes, the build's signing step will too.

If both envs fail, `make sign-test` prints the exact manual steps (install
`gnupg2-scdaemon`/`pinentry-curses`, add `disable-ccid`, restart pcscd, get the
public key into the keyring). The most common live-OS gap is the **public key**:
the card holds only the private half, and a fresh keyring must fetch it. Set a
durable URL once with `gpg --card-edit` → `admin` → `url <https-url>`, or import
from a file with `gpg --import`.

## Reclaiming disk after a build

A successful build leaves several large artifacts on the host (or live tmpfs):
the ISO in `out/`, possibly leftover `/tmp/safe-live-build-*` and
`/tmp/safe-live-gnupg-*` dirs, the
`localhost/safe-live-nixos-builder` container image, the `docker.io/nixos/nix`
base image, and the `safe-live-nix-store` cache volume (~1+ GB of packages).

To remove everything in one shot (double-prompt for safety):

```sh
make clean-all                              # default cache volume
CACHE_VOLUME=/mnt/nix-store make clean-all  # bind-mount path used during build
```

Pass the same `CACHE_VOLUME` you used at build time — otherwise the bind-mount
directory is left untouched (the named volume gets cleaned, your `/mnt/...`
path does not).

Lighter options if you want to keep the cache:

```sh
make clean                                    # just out/ and result
make clean-cache                              # remove the cache (honors CACHE_VOLUME)
CACHE_VOLUME=/mnt/nix-store make clean-cache  # remove the bind-mount cache directory
make gc                                       # nix-collect-garbage -d in the cache
```
