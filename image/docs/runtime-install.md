# Installing packages at runtime (emergency use)

> **This image is meant to be immutable.** The whole point of a verified
> live ISO is that what you boot is exactly what was signed and reproducibly
> built — anything you install at runtime breaks that guarantee.
>
> Use the recipes below only when you need a tool *right now* and rebuilding
> the ISO is not an option. As soon as you can, **add the package to
> `modules/base.nix` (or the relevant module) and rebuild the image** so the
> next boot has it baked in, signed, and reproducible.

## Prerequisites

You must be online and you must have a Nix store you can write to. The live
ISO ships with `nix-command` and `flakes` already enabled, and `nixpkgs`
resolves through the default flake registry.

```bash
sudo safe-netmode online
```

## Ephemeral — for "I need this once"

`nix shell` drops you into a sub-shell with the package on `$PATH`. Nothing
is registered in any profile; exit the shell and the package is unused
(though its store paths linger until the next `nix-collect-garbage`).

```bash
nix shell nixpkgs#htop                  # interactive
nix shell nixpkgs#imagemagick -c convert in.png out.jpg   # one-shot
```

Multiple packages at once:

```bash
nix shell nixpkgs#htop nixpkgs#iotop nixpkgs#nethogs
```

## Persistent for this boot only — `nix profile`

`nix profile add` adds the package to your *user* profile. It shows up on
`$PATH` for any new shell until you `nix profile remove` it — **or until
you reboot**, since the live ISO's home and profile state live on tmpfs.
(Older Nix versions used `install`; that name is deprecated in favor of
`add`.)

```bash
nix profile add nixpkgs#htop
nix profile list                        # what's installed
nix profile remove htop                 # or by index
```

## After the emergency

Bake the package in so this never happens again on this image:

1. Add it to the relevant module — for general CLI tools that's
   `modules/base.nix`'s `environment.systemPackages`.
2. `make build` to produce a fresh, signed ISO.
3. Re-verify and re-flash.

Pinning the dependency at build time (rather than `nix shell`ing it later)
is what keeps the image reproducible and signable — that property is the
whole reason this project exists.
