# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
if @pkgs_coreutils@/bin/env -i @preflight@ >/dev/null 2>&1; then
  echo "missing credentials were accepted" >&2
  exit 1
fi
@pkgs_coreutils@/bin/env -i @fixture@ @preflight@
if @pkgs_coreutils@/bin/env -i @fixture@ SLSKD_NO_AUTH=true @preflight@ >/dev/null 2>&1; then
  echo "disabled authentication was accepted" >&2
  exit 1
fi
if @pkgs_coreutils@/bin/env -i @fixture@ SLSKD_JWT_KEY=too-short @preflight@ >/dev/null 2>&1; then
  echo "short JWT key was accepted" >&2
  exit 1
fi
touch "$out"
