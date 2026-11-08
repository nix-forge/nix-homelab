# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/scripts/media project/tests/media
cp @scripts_media_install_jellyfin_plugins_py@ project/scripts/media/install_jellyfin_plugins.py
cp @scripts_media_maintainerr_policy_py@ project/scripts/media/maintainerr_policy.py
cp @scripts_media_jellyfin_ignore_py@ project/scripts/media/jellyfin_ignore.py
cp @tests_media_test_jellyfin_plugins_py@ project/tests/media/test_jellyfin_plugins.py
cp @tests_media_test_maintainerr_policy_py@ project/tests/media/test_maintainerr_policy.py
cp @tests_media_test_jellyfin_ignore_py@ project/tests/media/test_jellyfin_ignore.py
python3 -m unittest discover -s project/tests/media -v
touch "$out"
