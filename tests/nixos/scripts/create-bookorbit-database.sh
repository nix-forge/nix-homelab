# shellcheck shell=bash
set -eu
createdb -h /run/bookorbit-postgres -U bookorbit bookorbit
psql -X -v ON_ERROR_STOP=1 -h /run/bookorbit-postgres -U bookorbit -d bookorbit \
  -c 'CREATE EXTENSION vector; CREATE EXTENSION pg_trgm; CREATE EXTENSION "uuid-ossp";'
