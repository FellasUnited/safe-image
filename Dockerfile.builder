# Builder image for the NixOS ISO.
FROM docker.io/nixos/nix:2.34.6@sha256:e2fe74e96e965653c7b8f16ac64d1e56581c63c84d7fa07fb0692fd055cd06b0

RUN mkdir -p /etc/nix && \
    printf '%s\n' \
      'experimental-features = nix-command flakes' \
      'sandbox = false' \
      'filter-syscalls = false' \
      > /etc/nix/nix.conf

WORKDIR /src
CMD ["sh"]
