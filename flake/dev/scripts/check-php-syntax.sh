# shellcheck shell=bash
# Parse without loading application configuration or executing the script.
for source in "$@"; do
  php -n -l "$source"
done
