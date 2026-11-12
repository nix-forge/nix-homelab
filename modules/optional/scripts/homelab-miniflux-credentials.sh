# shellcheck shell=bash
umask 0077
target=@lib_escapeShellArg_generatedCredentialsFile@
if test -s "$target"; then
  exit 0
fi
partial="$target.partial.$$"
trap 'rm -f "$partial"' EXIT
password="$(openssl rand -hex 32)"
printf 'ADMIN_USERNAME=admin\nADMIN_PASSWORD=%s\n' "$password" >"$partial"
chmod 0400 "$partial"
mv "$partial" "$target"
trap - EXIT
