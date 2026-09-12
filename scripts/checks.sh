#!/usr/bin/env bash
set -euo pipefail

mode=${1:-evaluate}
if (($# > 0)); then
  shift
fi
case "$mode" in
evaluate)
  if (($# == 0)); then
    set -- x86_64-linux aarch64-linux
  fi
  ;;
build)
  if (($# == 0)); then
    set -- "$(nix eval --impure --raw --expr builtins.currentSystem)"
  fi
  ;;
*)
  printf 'Usage: %s [evaluate|build] [system ...]\n' "$0" >&2
  exit 2
  ;;
esac

# Separate Nix processes release evaluation memory between configurations.
for system in "$@"; do
  names=$(nix eval --raw ".#checks.${system}" --apply 'checks: builtins.concatStringsSep "\n" (builtins.attrNames checks)')
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    printf '%s %s.%s\n' "$mode" "$system" "$name"
    if [[ $mode == evaluate ]]; then
      nix eval --raw ".#checks.${system}.${name}.drvPath" >/dev/null
    else
      nix build --no-link --max-jobs 1 --cores 2 --print-build-logs ".#checks.${system}.${name}"
    fi
  done <<<"$names"
done

if [[ $mode == evaluate ]]; then
  nix eval --raw .#nixosConfigurations.vm-test-vpn.config.system.build.toplevel.drvPath >/dev/null
fi
