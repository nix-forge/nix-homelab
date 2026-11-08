# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp @scripts@/scrypted-api.cjs ./scrypted-api.cjs
cp @scripts@/scrypted-plugin-install.cjs ./scrypted-plugin-install.cjs
cp @scripts@/scrypted-plugin-marker.cjs ./scrypted-plugin-marker.cjs
cp @scripts@/scrypted-plugin-marker.test.cjs ./scrypted-plugin-marker.test.cjs
@cfg_package@/bin/scrypted-node ./scrypted-plugin-marker.test.cjs @serverRoot@
touch "$out"
