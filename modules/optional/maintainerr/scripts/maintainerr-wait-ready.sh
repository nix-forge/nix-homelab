# shellcheck shell=bash
for attempt in $(seq 1 60); do
  if curl --fail --silent --max-time 5 \
    http://127.0.0.1:@toString_cfg_backendPort@/api/health/ready >/dev/null; then
    exit 0
  fi
  if [ "$attempt" -lt 60 ]; then
    sleep 1
  fi
done
printf '%s\n' 'Maintainerr did not become ready after 60 readiness attempts.' >&2
exit 1
