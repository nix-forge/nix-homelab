{ config, lib, ... }: {
  config = lib.mkMerge [
    (lib.mkIf config.homelab.apps.navidrome.enable {
      services.navidrome.settings.MusicFolder = "${config.homelab.storage.libraryDir}/music";
      # Storage preparation owns this path after checking the real mount.
      systemd.tmpfiles.settings.navidromeDirs.${config.services.navidrome.settings.MusicFolder} =
        lib.mkForce
          { };
    })
    (lib.mkIf config.homelab.apps.audiobookshelf.enable {
      services.audiobookshelf.host = lib.mkDefault "127.0.0.1";
    })
  ];
}
