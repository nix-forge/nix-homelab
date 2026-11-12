# shellcheck shell=bash
if test -d @lib_escapeShellArg_config_services_name_dataDir@ &&
  @pkgs_findutils@/bin/find -H @lib_escapeShellArg_config_services_name_dataDir2@ -maxdepth 1 \( -type f -o -type l \) -name '*.db' -print -quit | @pkgs_gnugrep@/bin/grep -q .; then
  echo 'Existing SQLite state requires an attended migration before PostgreSQL can start.' >&2
  exit 1
fi
