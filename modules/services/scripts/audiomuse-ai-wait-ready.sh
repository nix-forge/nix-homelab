# shellcheck shell=bash
for attempt in $(seq 1 120); do
  if curl --fail --silent --max-time 5 \
    http://@cfg_host@:@toString_cfg_port@/api/health >/dev/null; then
    exit 0
  fi
  if [ "$attempt" -lt 120 ]; then
    sleep 1
  fi
done
printf '%s\n' 'AudioMuse-AI did not become ready after 120 readiness attempts.' >&2
exit 1
