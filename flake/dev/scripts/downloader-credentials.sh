# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/scripts project/tests
cp -r @scripts_downloaders@ project/scripts/downloaders
mkdir -p project/modules/optional/quality/custom-formats
mkdir -p project/modules/downloaders/scripts
cp @modules_downloaders_scripts_start_qbittorrent_sh@ project/modules/downloaders/scripts/start-qbittorrent.sh
cp @modules_optional_quality_custom_formats_subtitled_release_js@ project/modules/optional/quality/custom-formats/subtitled-release.json
cp -r @scripts_integration@ project/scripts/integration
cp -r @tests_downloaders@ project/tests/downloaders
chmod -R u+w project
python3 -B -m unittest discover -s project/tests/downloaders -v
touch "$out"
