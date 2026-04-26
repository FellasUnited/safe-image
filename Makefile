.PHONY: build build-no-sign build-no-cache sign sign-test verify test test-gui clean clean-cache clean-all gc

build:
	./si-build.sh

build-no-sign:
	SKIP_SIGN=1 ./si-build.sh

build-no-cache:
	USE_CACHE_VOLUME=0 ./si-build.sh

sign:
	./si-sign-outputs.sh

# Smoke-test signing (host env first, isolated temp env fallback) without a build.
sign-test:
	./si-sign-test.sh

verify:
	./si-verify.sh

test:
	./si-test.sh

test-gui:
	GUI=1 ./si-test.sh

clean:
	rm -rf out result

# GC the Nix store inside the cache volume. Runs without network (--net=none)
# so it works on a Fedora live OS where rootless pasta cannot remount /, and
# with --pull=never so podman never tries to fetch the local builder image.
# Run as the same user that built (rootless); sudo uses a separate image
# store where the builder image does not exist.
#
# Mounting the cache volume over /nix replaces the image's PATH targets,
# so we cannot rely on `sh` or on /nix/var/nix/profiles/default (the
# symlink may dangle after past GCs). Instead, glob the hashed Nix path
# in the volume on the host and pass it to --entrypoint.
gc:
	@ENGINE=$$(command -v podman 2>/dev/null || command -v docker); \
	 [ -n "$$ENGINE" ] || { echo "ERROR: podman or docker required."; exit 1; }; \
	 VOL_PATH=$$($$ENGINE volume inspect safe-live-nix-store --format '{{.Mountpoint}}' 2>/dev/null); \
	 [ -n "$$VOL_PATH" ] || { echo "ERROR: cache volume 'safe-live-nix-store' not found."; exit 1; }; \
	 NIX_BIN=$$(ls -d $$VOL_PATH/store/*-nix-[0-9]*/bin/nix-collect-garbage 2>/dev/null | head -1); \
	 [ -n "$$NIX_BIN" ] || { echo "ERROR: nix-collect-garbage not found in cache volume."; exit 1; }; \
	 CONTAINER_BIN=/nix$${NIX_BIN#$$VOL_PATH}; \
	 IMAGE=localhost/safe-live-nixos-builder; \
	 PULL_ARG=$$([ "$$(basename $$ENGINE)" = podman ] && echo --pull=never); \
	 $$ENGINE run --rm \
	   $$PULL_ARG \
	   --net=none \
	   --security-opt label=disable \
	   -v safe-live-nix-store:/nix \
	   --entrypoint $$CONTAINER_BIN \
	   $$IMAGE \
	   -d

clean-cache:
	@CACHE=$${CACHE_VOLUME:-safe-live-nix-store}; \
	 if [ "$${CACHE#/}" != "$$CACHE" ]; then \
	   echo "This will delete the Nix store cache at $$CACHE (bind-mount path)."; \
	 else \
	   echo "This will delete the Nix store cache volume ($$CACHE)."; \
	 fi; \
	 echo "Your project files are NOT affected. The next build will re-download"; \
	 echo "all Nix packages (~1 GB) from cache.nixos.org."; echo; \
	 printf "Are you sure? [y/N] " && read ans && [ "$$ans" = y ] || [ "$$ans" = Y ] || { echo "Aborted."; exit 1; }; \
	 printf "Confirm again — this cannot be undone: [y/N] " && read ans && [ "$$ans" = y ] || [ "$$ans" = Y ] || { echo "Aborted."; exit 1; }; \
	 if [ "$${CACHE#/}" != "$$CACHE" ]; then \
	   sudo rm -rf "$$CACHE" && echo "Cache directory removed."; \
	 else \
	   podman volume rm "$$CACHE" 2>/dev/null || docker volume rm "$$CACHE" 2>/dev/null || true; \
	   echo "Cache volume removed."; \
	 fi

# Reclaim all disk space used by builds: out/, result, leftover /tmp build
# dirs (when a previous run was killed before its trap fired), the builder
# container image, the upstream nixos/nix base image, and the Nix store
# cache volume. Two prompts because this is non-recoverable.
clean-all:
	@CACHE=$${CACHE_VOLUME:-safe-live-nix-store}; \
	 echo "This will remove ALL build-related state:"; \
	 echo "  - out/ and result"; \
	 echo "  - /tmp/safe-live-build-* and /tmp/safe-live-gnupg-* (leftover temp dirs)"; \
	 echo "  - container image localhost/safe-live-nixos-builder"; \
	 echo "  - base image docker.io/nixos/nix (pinned digest)"; \
	 if [ "$${CACHE#/}" != "$$CACHE" ]; then \
	   echo "  - Nix store cache directory $$CACHE (bind-mount path)"; \
	 else \
	   echo "  - Nix store cache volume $$CACHE"; \
	 fi; echo; \
	 echo "Your project source files are NOT affected. The next build will"; \
	 echo "re-pull the base image and re-download Nix packages (~1+ GB)."; echo; \
	 printf "Are you sure? [y/N] " && read ans && [ "$$ans" = y ] || [ "$$ans" = Y ] || { echo "Aborted."; exit 1; }; \
	 printf "Confirm again — this cannot be undone: [y/N] " && read ans && [ "$$ans" = y ] || [ "$$ans" = Y ] || { echo "Aborted."; exit 1; }; \
	 rm -rf out result; \
	 rm -rf /tmp/safe-live-build-* /tmp/safe-live-gnupg-* 2>/dev/null || true; \
	 ENGINE=$$(command -v podman 2>/dev/null || command -v docker); \
	 if [ -n "$$ENGINE" ]; then \
	   $$ENGINE rmi -f localhost/safe-live-nixos-builder 2>/dev/null || true; \
	   $$ENGINE rmi -f docker.io/nixos/nix:2.34.6 2>/dev/null || true; \
	   if [ "$${CACHE#/}" != "$$CACHE" ]; then \
	     sudo rm -rf "$$CACHE" 2>/dev/null || true; \
	   else \
	     $$ENGINE volume rm "$$CACHE" 2>/dev/null || true; \
	   fi; \
	 else \
	   echo "No podman/docker; skipping image+volume cleanup."; \
	 fi; \
	 echo "All build state removed."
