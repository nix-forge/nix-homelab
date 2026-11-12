# shellcheck shell=bash
install -D -m 0600 "$CREDENTIALS_DIRECTORY/realm" @lib_escapeShellArg_destination@
mkdir -p /run/keycloak/data/import
ln -sf @lib_escapeShellArg_destination@ /run/keycloak/data/import/@bootstrap_name@-realm.json
