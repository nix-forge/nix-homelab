# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out"
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i color=c=blue:s=1920x1080:r=1 \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -t 120 -c:v mpeg4 -c:a aac "$out"/Workflow.Fixture.2026.1080p.WEB-DL.mkv
