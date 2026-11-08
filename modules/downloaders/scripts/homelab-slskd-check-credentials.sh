# shellcheck shell=bash
set -eu
for name in SLSKD_SLSK_USERNAME SLSKD_SLSK_PASSWORD SLSKD_USERNAME SLSKD_PASSWORD SLSKD_API_KEY SLSKD_JWT_KEY; do
  if [ -z "${!name:-}" ]; then
    echo "slskd requires $name in its runtime credential file" >&2
    exit 1
  fi
done
if [ "${#SLSKD_SLSK_PASSWORD}" -lt 12 ] || [ "${#SLSKD_PASSWORD}" -lt 16 ] ||
  [ "${#SLSKD_API_KEY}" -lt 16 ] || [ "${#SLSKD_JWT_KEY}" -lt 32 ]; then
  echo "slskd runtime credentials are too short" >&2
  exit 1
fi
if [ "$SLSKD_PASSWORD" = slskd ] || [ "${SLSKD_NO_AUTH:-false}" != false ] ||
  [ "${SLSKD_REMOTE_CONFIGURATION:-false}" != false ]; then
  echo "slskd must keep authenticated, immutable web configuration" >&2
  exit 1
fi
if [ -n "${SLSKD_HTTP_IP_ADDRESS:-}" ] &&
  [ "$SLSKD_HTTP_IP_ADDRESS" != @lib_escapeShellArg_webAddress@ ]; then
  echo "slskd web address must remain on the private host link" >&2
  exit 1
fi
