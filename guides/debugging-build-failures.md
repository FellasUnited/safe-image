# Debugging build failures

When `nix build` fails inside the container, Nix prints the failed derivation
path and tells you to run `nix log <drv>` for the full log.  That command must
be run **inside the builder container** because the Nix store lives in the
`safe-live-nix-store` volume, not on the host.

## Open an interactive shell in the builder container

```sh
podman run --rm -it \
  --security-opt label=disable \
  --network=host \
  -v safe-live-nix-store:/nix \
  -v "$(pwd):/src:ro,Z" \
  -w /src \
  safe-live-nixos-builder \
  sh -l
```

The builder image must already exist (run `make build-no-sign` once, or
`podman build -f Dockerfile.builder -t safe-live-nixos-builder .`).

## Retrieve the build log

Copy the `.drv` path from the error output, e.g.:

```
error: Cannot build '/nix/store/28wi1fx8c…-safe-live-…iso.drv'.
```

Then inside the shell:

```sh
nix log /nix/store/28wi1fx8c…-safe-live-…iso.drv
```

`nix log` streams the full build output — xorriso errors, mksquashfs
diagnostics, etc. — that is truncated in the normal build output.

## Run an ad-hoc build inside the shell

```sh
nix build .#nixosConfigurations.safe-live.config.system.build.isoImage \
  --out-link /tmp/result --no-warn-dirty -L
```

`-L` (keep-going + verbose) prints each builder's output live, which is useful
when you want to watch the failure in real time rather than retrieve it after
the fact.

## Garbage-collect stale derivations

Every failed or superseded build leaves derivations in the Nix store volume.
From the host:

```sh
make gc          # runs nix-collect-garbage -d inside the builder container
```

Or directly inside the shell:

```sh
nix-collect-garbage -d
```
