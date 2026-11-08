{ pkgs }:
pkgs.runCommand "bookorbit-schema-notifications"
  { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.psycopg2 ])) ]; }
  ''
    python3 ${./fixtures/bookorbit_schema_check.py} \
      ${pkgs.postgresql_18}/bin/postgres ${pkgs.postgresql_18}/bin/initdb \
      ${../modules/services/scripts/bookorbit_schema_ready.py} \
      ${../modules/services/scripts/bookorbit-schema-notifications.sql}
    touch "$out"
  ''
