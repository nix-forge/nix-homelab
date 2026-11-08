# shellcheck shell=bash
@pkgs_coreutils@/bin/chmod 0700 /var/lib/recyclarr
@pkgs_coreutils@/bin/chmod 0600 /var/lib/recyclarr/config.yml
@pkgs_coreutils@/bin/install -m 0600 @guideSettings@ /var/lib/recyclarr/settings.yml
