# shellcheck shell=bash
umask 077
printf '%s' 0123456789abcdef0123456789abcdef >/run/arr-fixture-api
