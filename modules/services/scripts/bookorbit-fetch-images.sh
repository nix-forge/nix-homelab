# shellcheck shell=bash
# Nix renders the placeholder as a complete argument list.
# shellcheck disable=SC2043
export PATH="/run/wrappers/bin:$PATH"
for image in @lib_escapeShellArgs_appImage_dbImage@; do
  if ! podman image exists "$image"; then
    podman pull "$image"
  fi
done
