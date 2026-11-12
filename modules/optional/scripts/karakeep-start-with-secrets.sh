# shellcheck shell=bash
set -eu
MEILI_MASTER_KEY="$(@lib_getExe_pkgs_coreutils_cat@ @lib_escapeShellArg_meiliMasterKeyFile@)"
export MEILI_MASTER_KEY
NEXTAUTH_SECRET="$(@lib_getExe_pkgs_coreutils_cat@ @lib_escapeShellArg_nextAuthSecretFile@)"
export NEXTAUTH_SECRET
exec @executable@
