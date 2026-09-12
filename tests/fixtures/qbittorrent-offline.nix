{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Local fixtures use explicit peers. Disable discovery before the first start.
  services.qbittorrent.serverConfig.BitTorrent.Session = {
    DHTEnabled = false;
    PeXEnabled = false;
    LSDEnabled = false;
  };
  # Native config installation runs at 1000; the credential merge runs at 1500.
  systemd.services.qbittorrent.serviceConfig.ExecStartPre = lib.mkOrder 1600 [
    (pkgs.writeShellScript "qbit-fixture-discovery-check" ''
      for preference in DHTEnabled PeXEnabled LSDEnabled; do
        test "$(${pkgs.crudini}/bin/crudini --get ${lib.escapeShellArg "${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf"} BitTorrent "Session\\$preference")" = false
      done
    '')
  ];
}
