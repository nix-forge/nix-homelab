# shellcheck shell=bash
@config_services_postgresql_package@/bin/psql --host @postgresSocket@ --port @postgresPort@ --dbname postgres --set ON_ERROR_STOP=1 --command 'ALTER DATABASE "@account_name@-logs" OWNER TO "@account_name@";'
