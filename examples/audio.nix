# Audio players with private user-supplied credentials and explicit libraries.
{ config, ... }:
let
  secret = name: { _secret = "/run/nix-seal/system/secrets/${name}"; };
in
{
  # Contains a stable ND_PASSWORDENCRYPTIONKEY. Preserve this key with the
  # encrypted host secret catalog; do not rotate it as an ordinary API password.
  services.navidrome.environmentFile = "/run/nix-seal/system/secrets/navidrome.env";
  homelab = {
    apps.navidrome.enable = true;
    apps.audiobookshelf.enable = true;
    integration = {
      enable = true;
      services.navidrome = {
        url = "http://127.0.0.1:${toString config.services.navidrome.settings.Port}";
        mode = "managed";
        settings = {
          login = {
            username = "admin";
            password = secret "navidrome-admin-password";
          };
          users.listener = {
            name = "Listener";
            password = secret "navidrome-listener-password";
            isAdmin = false;
          };
        };
      };
      services.audiobookshelf = {
        url = "http://127.0.0.1:${toString config.services.audiobookshelf.port}";
        mode = "managed";
        settings = {
          login = {
            username = "admin";
            password = secret "audiobookshelf-admin-password";
          };
          libraries = {
            Audiobooks = {
              folders = [ { fullPath = "${config.homelab.storage.libraryDir}/audiobooks"; } ];
              mediaType = "book";
              icon = "audiobooks";
            };
            Podcasts = {
              folders = [ { fullPath = "${config.homelab.storage.downloadsDir}/podcasts"; } ];
              mediaType = "podcast";
              icon = "podcast";
            };
          };
          users.listener = {
            password = secret "audiobookshelf-listener-password";
            type = "user";
            isActive = true;
            permissions = {
              download = false;
              upload = false;
              update = false;
              delete = false;
              accessAllLibraries = true;
              accessAllTags = true;
            };
          };
        };
      };
    };
  };
}
