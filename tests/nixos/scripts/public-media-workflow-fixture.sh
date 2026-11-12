# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out"
openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
  -subj /CN=public-workflow-fixture \
  -addext 'subjectAltName=DNS:api.radarr.video,DNS:api.themoviedb.org' \
  -keyout "$out"/key.pem -out "$out"/cert.pem
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i color=c=blue:s=1920x1080:r=1 \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -t 120 -c:v mpeg4 -c:a aac "$out"/Workflow.Fixture.2026.1080p.WEB-DL.mkv
