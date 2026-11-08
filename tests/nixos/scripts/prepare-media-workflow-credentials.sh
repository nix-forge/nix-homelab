# shellcheck shell=bash
umask 077
printf 0123456789abcdef0123456789abcdef >/run/workflow-api-key
printf public-workflow-password >/run/workflow-password
@pkgs_python3@/bin/python @pythonCheck1@
