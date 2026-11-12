# shellcheck shell=bash
set -eu
for preference in DHTEnabled PeXEnabled LSDEnabled; do
  test "$(@pkgs_crudini@/bin/crudini --get @lib_escapeShellArg_config_services_qbittorrent_profileDir_qB@ BitTorrent "Session\\$preference")" = false
done
