# shellcheck shell=bash
# Nix renders the placeholder as a complete argument list.
setfacl -m u:bookorbit:--x @lib_escapeShellArg_storage_rootDir@ @lib_escapeShellArg_storage_libraryDir@
# shellcheck disable=SC2043
for media_dir in @lib_escapeShellArgs_storage_mediaDirs@; do
  setfacl -m u:bookorbit:r-x,d:u:bookorbit:r-x "$media_dir"
done
@lib_optionalString_acquisition_enable_old_dock_lib_escapeShe@
