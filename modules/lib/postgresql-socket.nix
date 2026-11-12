# Select a filesystem socket from PostgreSQL's comma-separated socket settings.
# Abstract-only and noncanonical socket configurations need an owning assertion.
lib: settings:
let
  runtimePath = import ./runtime-path.nix lib;
  directories = map (
    value:
    let
      trimmed = lib.trim value;
    in
    if lib.hasPrefix "\"" trimmed && lib.hasSuffix "\"" trimmed then
      lib.removeSuffix "\"" (lib.removePrefix "\"" trimmed)
    else if lib.hasInfix "\"" trimmed then
      ""
    else
      trimmed
  ) (lib.splitString "," (settings.unix_socket_directories or "/run/postgresql"));
in
lib.findFirst (
  path: runtimePath path && builtins.match "/[A-Za-z0-9_./-]+" path != null
) null directories
