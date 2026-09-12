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
  systemd.services.qbittorrent.preStart = lib.mkAfter ''
    for preference in DHTEnabled PeXEnabled LSDEnabled; do
      test "$(${pkgs.crudini}/bin/crudini --get ${lib.escapeShellArg "${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf"} BitTorrent "Session\\$preference")" = false
    done
  '';
}
