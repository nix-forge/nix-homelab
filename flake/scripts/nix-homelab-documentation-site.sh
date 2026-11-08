# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p source/docs/generated source/examples
cp @site_mkdocs_yml@ mkdocs.yml
cp @site_rewrite_source_links_py@ rewrite_source_links.py
cp @rEADME_md@ source/index.md
cp @sECURITY_md@ source/SECURITY.md
cp @cONTRIBUTING_md@ source/CONTRIBUTING.md
cp -r @docs@/. source/docs/
cp -r @examples@/. source/examples/
cp @self_packages_system_options_markdown@ source/docs/generated/options.md
cp @self_packages_system_support_matrix@ source/docs/generated/support-matrix.md
mkdocs build --config-file mkdocs.yml --site-dir "$out" --strict
test -s "$out/index.html"
test -s "$out/search/search_index.json"
