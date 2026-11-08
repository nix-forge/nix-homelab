# shellcheck shell=bash
test "$MEILI_MASTER_KEY" = "$(cat /var/lib/karakeep/meili-master-key)"
test "$NEXTAUTH_SECRET" = "$(cat /var/lib/karakeep/nextauth-secret)"
exec @pkgs_coreutils@/bin/sleep infinity
