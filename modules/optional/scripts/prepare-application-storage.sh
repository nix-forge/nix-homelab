# shellcheck shell=bash
paths=(@lib_escapeShellArgs_guardedDirs@)
if ((${#paths[@]} > 0)); then
  @pkgs_python3@/bin/python3 @scripts_storage_prepare_py@ @lib_escapeShellArg_storage_group@ "${paths[@]}"
fi
