# Import in a host that already imports and configures nix-seal.
# The user supplies encrypted sources and prepares the signed target artifacts.
{ config, ... }: {
  nixSeal.secrets = {
    "homelab-vpn-private-key" = {
      phase = "services";
      restartUnits = [ "wireguard-${config.homelab.vpn.interface.name}.service" ];
    };
    "homelab-qbittorrent-webui" = {
      phase = "services";
      restartUnits = [ "qbittorrent.service" ];
    };
  };
  homelab.vpn.interface.privateKeyFile = config.nixSeal.secrets."homelab-vpn-private-key".path;
  homelab.apps.qbittorrent.credentialsFile = config.nixSeal.secrets."homelab-qbittorrent-webui".path;
  systemd.services."wireguard-${config.homelab.vpn.interface.name}" = {
    after = [ "nix-seal-activate.service" ];
    requires = [ "nix-seal-activate.service" ];
  };
  systemd.services.qbittorrent = {
    after = [ "nix-seal-activate.service" ];
    requires = [ "nix-seal-activate.service" ];
  };
}
