#!/usr/bin/env bash
set -euo pipefail
case "${1:-evaluate}" in
evaluate) nix flake check --no-build ;;
build) nix flake check ;;
*)
  echo "usage: $0 [evaluate|build]" >&2
  exit 2
  ;;
esac
