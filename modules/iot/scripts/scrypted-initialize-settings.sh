# shellcheck shell=bash
test -e @authCheck@
test -e @settingsCheck@
@lib_optionalString_cfg_plugins_test_e_markerCheck@
@lib_getExe_cfg_nodePackage_node@ @scripts@/scrypted-auth.cjs \
  @serverRoot@ "$CREDENTIALS_DIRECTORY/ui-username" \
  "$CREDENTIALS_DIRECTORY/ui-password" @stateDir@
@lib_getExe_cfg_nodePackage_node@ @scripts@/scrypted-managed-settings.cjs \
  @serverRoot@ @stateDir@ @lib_escapeShellArg_cfg_listenAddress@
@lib_optionalString_cfg_plugins_lib_getExe_cfg_nodePackage_no@
