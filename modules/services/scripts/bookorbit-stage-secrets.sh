# shellcheck shell=bash
# Nix renders the placeholder as a complete argument list.
# shellcheck disable=SC2043
set -eu
umask 077
for name in @appSecrets@; do
  partial="$(mktemp "@secretRuntime@/$name.XXXXXX")"
  trap 'rm -f "$partial"' EXIT
  cat "$CREDENTIALS_DIRECTORY/$name" >"$partial"
  chmod 0400 "$partial"
  mv -f "$partial" "@secretRuntime@/$name"
  trap - EXIT
done
