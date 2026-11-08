# shellcheck shell=bash
exec sudo -u wardrowbe-codex @lib_getExe_pkgs_coreutils_env@ \
  HOME=/var/lib/wardrowbe-codex CODEX_HOME=/var/lib/wardrowbe-codex \
  @lib_getExe_ai_codex_package@ login --device-auth \
  -c 'cli_auth_credentials_store="file"' -c 'forced_login_method="chatgpt"'
