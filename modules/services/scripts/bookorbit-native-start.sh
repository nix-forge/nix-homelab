# shellcheck shell=bash
set -eu
JWT_SECRET="$(@pkgs_coreutils@/bin/cat @runtimeSecret_jwt_secret@)"
export JWT_SECRET
SETUP_BOOTSTRAP_TOKEN="$(@pkgs_coreutils@/bin/cat @runtimeSecret_setup_token@)"
export SETUP_BOOTSTRAP_TOKEN
BOOK_REQUEST_ENCRYPTION_KEY="$(@pkgs_coreutils@/bin/cat @runtimeSecret_request_key@)"
export BOOK_REQUEST_ENCRYPTION_KEY
PODCAST_ENCRYPTION_KEY="$(@pkgs_coreutils@/bin/cat @runtimeSecret_podcast_key@)"
export PODCAST_ENCRYPTION_KEY
exec @lib_getExe_config_services_bookorbit_package@
