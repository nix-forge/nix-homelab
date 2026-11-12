# shellcheck shell=bash
export FRESHRSS_PACKAGE=@lib_escapeShellArg_toString_package@
flags=(--auth-type form
  --base-url @lib_escapeShellArg_config_services_freshrss_baseUrl@
  --language @lib_escapeShellArg_config_services_freshrss_language@
  --db-type sqlite)
if test -f @lib_escapeShellArg_stateDir_config_php@; then
  ./cli/reconfigure.php "${flags[@]}"
else
  ./cli/prepare.php
  # This installation sentinel has no login account or credentials.
  ./cli/do-install.php --default-user provision_pending "${flags[@]}" >/dev/null
fi
@lib_getExe_config_services_phpfpm_phpPackage@ @scripts_optional_provision_freshrss_user_php@
