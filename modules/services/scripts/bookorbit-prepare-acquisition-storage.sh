# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables. Nix renders complete argument lists.
# shellcheck disable=SC2043
old_dock=@lib_escapeShellArg_home_data_book_dock@
if [ -d "$old_dock" ] && [ -n "$(find "$old_dock" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo "Move existing Book Dock items before changing its storage path" >&2
  exit 1
fi
install -d -m 2770 -o qbittorrent -g @lib_escapeShellArg_storage_group@ @lib_escapeShellArg_builtins_dirOf_acquisition_downloadDir@
setfacl -m u:bookorbit:rwx,d:u:bookorbit:rwx @lib_escapeShellArg_builtins_dirOf_acquisition_downloadDir@
install -d -m 0700 -o bookorbit -g bookorbit @lib_escapeShellArg_acquisition_dockDir@
install -d -m 2770 -o qbittorrent -g @lib_escapeShellArg_storage_group@ @lib_escapeShellArg_acquisition_downloadDir@
if [ "$(stat -c %d @lib_escapeShellArg_acquisition_dockDir@)" != "$(stat -c %d @lib_escapeShellArg_acquisition_downloadDir@)" ]; then
  echo "Book Dock and qBittorrent category must share a filesystem" >&2
  exit 1
fi
for media_dir in @lib_escapeShellArgs_acquisition_writableMediaDirs@; do
  if [ "$(stat -c %d "$media_dir")" != "$(stat -c %d @lib_escapeShellArg_acquisition_dockDir@)" ]; then
    echo "Writable book libraries must share the Book Dock filesystem" >&2
    exit 1
  fi
  setfacl -m u:bookorbit:rwx,d:u:bookorbit:rwx "$media_dir"
done
setfacl -m u:bookorbit:rwx,d:u:bookorbit:rwx @lib_escapeShellArg_acquisition_downloadDir@
