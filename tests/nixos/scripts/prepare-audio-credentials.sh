# shellcheck shell=bash
install -d -m 0700 /run/nix-seal/system/secrets
for name in navidrome-admin-password navidrome-listener-password audiobookshelf-admin-password audiobookshelf-listener-password; do
  printf '%s' 'public-disposable-audio-password' >/run/nix-seal/system/secrets/$name
  chmod 0600 /run/nix-seal/system/secrets/$name
done
printf '%s\n' 'ND_PASSWORDENCRYPTIONKEY=public-disposable-audio-encryption-key' >/run/nix-seal/system/secrets/navidrome.env
chmod 0600 /run/nix-seal/system/secrets/navidrome.env
