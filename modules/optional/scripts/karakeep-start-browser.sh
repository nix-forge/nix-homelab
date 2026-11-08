# shellcheck shell=bash
export HOME="$CACHE_DIRECTORY"
exec @browser_exe@ \
  --headless \
  --disable-gpu \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port=@toString_browser_port@ \
  --hide-scrollbars \
  --user-data-dir="$STATE_DIRECTORY"
