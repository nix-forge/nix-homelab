# shellcheck shell=bash
# The bounded retry count is intentionally unused.
# shellcheck disable=SC2034
for attempt in $(@pkgs_coreutils@/bin/seq 1 30); do
  if @pkgs_curl@/bin/curl --fail --silent http://127.0.0.1:18999/feed.xml >/dev/null; then
    exit 0
  fi
  @pkgs_coreutils@/bin/sleep 1
done
exit 1
