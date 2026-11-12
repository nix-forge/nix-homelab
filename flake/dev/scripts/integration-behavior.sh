# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/scripts project/tests
mkdir -p project/modules/optional/quality/custom-formats
cp @modules_optional_quality_custom_formats_subtitled_release_js@ project/modules/optional/quality/custom-formats/subtitled-release.json
cp -r @scripts_integration@ project/scripts/integration
cp -r @tests_integration@ project/tests/integration
mkdir -p project/tests/fixtures
cp @tests_fixtures_autobrr_runtime_py@ project/tests/fixtures/autobrr_runtime.py
chmod -R u+w project
python3 -m unittest discover -s project/tests/integration -v
touch "$out"
