# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp @scripts@/scrypted-api.cjs ./scrypted-api.cjs
cp @source@ ./@builtins_baseNameOf_source@
cp @test@ ./@builtins_baseNameOf_test@
@cfg_package@/bin/scrypted-node ./@builtins_baseNameOf_test@ @serverRoot@
touch "$out"
