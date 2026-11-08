# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out"
ffmpeg -hide_banner -loglevel error -f lavfi -i sine=frequency=440:duration=3 \
  -metadata title='Public fixture' -metadata artist='Fixture' -metadata album='Fixture' "$out"/fixture.flac
