# shellcheck shell=bash
for source in "$@"; do
  sql-formatter --language sqlite --fix "$source"
done
