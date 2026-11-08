# shellcheck shell=bash
install -d -m 0700 /run/nix-seal/system/secrets
umask 077
printf '%s\n' 'ControlUsername=operator' 'ControlPassword=public-original-password' >/run/nix-seal/system/secrets/nzbget-credentials.conf
printf '%s\n' '[misc]' 'api_key = public-sab-fixture-api-key' 'nzb_key = public-sab-fixture-nzb-key' 'username = operator' 'password = public-sab-fixture-password' >/run/nix-seal/system/secrets/sabnzbd.ini
