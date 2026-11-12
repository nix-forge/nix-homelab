{ config, lib, ... }:
let
  native = config.services.postgresql;
  socket = (import ../lib/postgresql-socket.nix lib) native.settings;
in
{
  # Native setup uses libpq's default socket unless PGHOST is supplied.
  # Keep database/user provisioning on the same server as homelab clients.
  config = lib.mkIf (native.enable && socket != null) {
    systemd.services.postgresql-setup.environment.PGHOST = lib.mkDefault socket;
  };
}
