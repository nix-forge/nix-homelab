# shellcheck shell=bash
# Preserve timestamps for clean SQL: treefmt uses them to detect CI changes.
dialect="$1"
shift
formatted="$(mktemp)"
trap 'rm -f -- "$formatted"' EXIT
for source in "$@"; do
  sql-formatter --language "$dialect" "$source" >"$formatted" || exit "$?"
  if ! cmp -s -- "$source" "$formatted"; then
    cat "$formatted" >"$source"
  fi
done
