# shellcheck shell=bash
@lib_getExe_cfg_nodePackage_node@ @scripts@/scrypted-plugin-install.cjs @manifest@ \
  "$CREDENTIALS_DIRECTORY/ui-username" \
  "$CREDENTIALS_DIRECTORY/ui-password" @stateDir@
