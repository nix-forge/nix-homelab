# shellcheck shell=bash
@lib_getExe_config_services_phpfpm_phpPackage@ @package@/cli/reconfigure.php \
  --api-enabled @lib_boolToString_cfg_apiEnabled@ --disable_update true \
  --allow_anonymous false --allow_anonymous_refresh false
