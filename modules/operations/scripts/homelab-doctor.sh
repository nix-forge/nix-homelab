# shellcheck shell=bash
exec python3 @scripts_operations_health_py@ --check @doctorSpecification@ "$@"
