# shellcheck shell=bash
test -e @uiAuthCompatibility@
if [ ! -e "@storage@/config.json" ]; then
  install -d -m 700 -o @lib_escapeShellArg_config_services_homebridge_user@ -g @lib_escapeShellArg_config_services_homebridge_group@ @lib_escapeShellArg_storage@
  @lib_getExe_cfg_nodePackage_node@ @scripts@/homebridge-initialize.cjs @lib_escapeShellArg_storage_config_json@
  chown @lib_escapeShellArg_config_services_homebridge_user@:@lib_escapeShellArg_config_services_homebridge_group@ @lib_escapeShellArg_storage_config_json@
fi
@lib_getExe_pkgs_python3@ @scripts_homebridge_ui_auth_py@ \
  "$CREDENTIALS_DIRECTORY/ui-username" \
  "$CREDENTIALS_DIRECTORY/ui-password" \
  @lib_escapeShellArg_storage_auth_json@
chown @lib_escapeShellArg_config_services_homebridge_user@:@lib_escapeShellArg_config_services_homebridge_group@ @lib_escapeShellArg_storage_auth_json@
@lib_optionalString_vesyncEnabled_lib_getExe_pkgs_python3_scr@
