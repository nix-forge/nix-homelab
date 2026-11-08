# shellcheck shell=bash
set -eu
fragment="$(@pkgs_coreutils@/bin/mktemp "$RUNTIME_DIRECTORY/.webui-credentials.XXXXXX")"
trap '@pkgs_coreutils@/bin/rm -f "$fragment"' EXIT
@pkgs_python3@/bin/python3 @scripts_downloaders_qbittorrent_credentials_py@ \
  "$CREDENTIALS_DIRECTORY/webui" "$fragment"
@pkgs_crudini@/bin/crudini --merge @lib_escapeShellArg_config_services_qbittorrent_profileDir_qB@ <"$fragment"
