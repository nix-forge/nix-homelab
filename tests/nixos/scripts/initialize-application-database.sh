# shellcheck shell=bash
@pkgs_sqlite@/bin/sqlite3 /var/lib/fixture/application.db 'CREATE TABLE IF NOT EXISTS requests (title TEXT);'
