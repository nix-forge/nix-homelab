{
  imports = [
    ./apps.nix
    ./profiles.nix
    ./storage
    ./arrs
    ./downloaders/nzbget.nix
    ./downloaders/sabnzbd.nix
    ./downloaders/qbittorrent.nix
    ./indexers/prowlarr.nix
    ./indexers/proxy.nix
    ./media
    ./request/seerr.nix
    ./vpn/wireguard.nix
  ];
}
