# shellcheck shell=bash
umask 0077

create_secret() {
  target="$1"
  if [ ! -s "$target" ]; then
    partial="$target.partial.$$"
    trap 'rm -f "$partial"' EXIT
    openssl rand -base64 36 >"$partial"
    chmod 0400 "$partial"
    mv "$partial" "$target"
    trap - EXIT
  fi
}

create_secret @lib_escapeShellArg_meiliMasterKeyFile@
create_secret @lib_escapeShellArg_nextAuthSecretFile@

settings_partial=@lib_escapeShellArg_settingsFile@.partial.$$
trap 'rm -f "$settings_partial"' EXIT
printf 'MEILI_MASTER_KEY=%s\nNEXTAUTH_SECRET=%s\n' \
  "$(tr -d '\n' <@lib_escapeShellArg_meiliMasterKeyFile@)" \
  "$(tr -d '\n' <@lib_escapeShellArg_nextAuthSecretFile@)" \
  >"$settings_partial"
chmod 0400 "$settings_partial"
mv "$settings_partial" @lib_escapeShellArg_settingsFile@
trap - EXIT
