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
    (toString (
      pkgs.writeShellScript "qbit-fixture-discovery-check" (
        (import ../../lib/render-text.nix) ./scripts/qbittorrent-check-disabled-discovery.sh {
          pkgs_crudini = pkgs.crudini;
          lib_escapeShellArg_config_services_qbittorrent_profileDir_qB = lib.escapeShellArg "${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf";
        }
      )
    ))
  ];
}
