# shellcheck shell=bash
test "$AUDIOMUSE_HOST" = 127.0.0.1
test "$AUDIOMUSE_PORT" = 18000
test "$PLUGIN_ALLOW_PIP" = false
test "$POSTGRES_HOST" = /run/postgresql
exec python3 @pkgs_writeText_audiomuse_test_server_py_builtins_readFile_sc@
