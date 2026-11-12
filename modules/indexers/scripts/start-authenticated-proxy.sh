# shellcheck shell=bash
export MICROSOCKS_USERNAME_FILE="$CREDENTIALS_DIRECTORY/MICROSOCKS_USERNAME_FILE"
export MICROSOCKS_PASSWORD_FILE="$CREDENTIALS_DIRECTORY/MICROSOCKS_PASSWORD_FILE"
exec @lib_optionalString_config_services_microsocks_execWrapper_nu@@config_services_microsocks_package@/bin/microsocks \
  -i @lib_escapeShellArg_vpn_namespace_bindAddress@ -p @toString_cfg_port@ -q
