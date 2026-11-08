# shellcheck shell=bash
exec python3 @scripts_operations_restore_postgres_py@ @inventory@ @restoreConfig@ "$@"
