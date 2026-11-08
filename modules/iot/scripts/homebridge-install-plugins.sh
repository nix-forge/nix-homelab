# shellcheck shell=bash
@lib_getExe_pkgs_util_linux_runuser@ \
  -u @lib_escapeShellArg_cfg_user@ -g @lib_escapeShellArg_cfg_group@ -- \
  @lib_getExe_pkgs_python3@ @scripts_homebridge_plugins_py@ \
  @manifest@ @lib_escapeShellArg_cfg_pluginPath@ \
  @lib_escapeShellArg_cfg_user@ @lib_escapeShellArg_cfg_group@
