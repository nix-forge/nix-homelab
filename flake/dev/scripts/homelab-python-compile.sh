# shellcheck shell=bash
cache="$(@lib_getExe_pkgs_coreutils_mktemp@ -d)"
trap '@lib_getExe_pkgs_coreutils_rm@ -rf -- "$cache"' EXIT
PYTHONPYCACHEPREFIX="$cache" @lib_getExe_pkgs_python3@ -m compileall -q .github flake fuzz modules scripts site tests
