{
  evaluate,
  lib,
  pkgs,
}:
let
  empty = (evaluate { }).config;
  webAuth =
    (evaluate {
      homelab.integration.webAuth.sonarr = {
        url = "http://127.0.0.1:8989";
        usernameFile = "/run/credentials/sonarr-username";
        passwordFile = "/run/credentials/sonarr-password";
        apiKeyFile = "/run/credentials/sonarr-api-key";
        after = [ "homelab-integrate-sonarr.service" ];
      };
    }).config;
  alias =
    (evaluate {
      homelab.integration.webAuth.sonarr-anime = {
        kind = "sonarr";
        serviceUnit = "sonarr-anime.service";
        url = "http://127.0.0.1:8990";
        usernameFile = "/run/credentials/anime-username";
        passwordFile = "/run/credentials/anime-password";
        apiKeyFile = "/run/credentials/anime-api-key";
      };
    }).config;
  invalidWebAuth =
    (evaluate {
      homelab.integration.webAuth.sonarr = {
        url = "http://127.0.0.1:8989";
        usernameFile = "/nix/store/unsafe-username";
        passwordFile = "/run/credentials/password";
        apiKeyFile = "/run/credentials/key";
      };
    }).config;
  artwork =
    (evaluate {
      services.navidrome.enable = true;
      homelab.music.artwork = {
        enable = true;
        libraryDir = "/srv/media/music";
        onUnitActiveSec = "12h";
      };
    }).config;
  lyrics =
    (evaluate {
      services.navidrome.enable = true;
      homelab.storage.enable = true;
      homelab.music.lyrics.enable = true;
    }).config;
  invalidLyrics = (evaluate { homelab.music.lyrics.enable = true; }).config;
  invalidLyricsPath =
    (evaluate {
      services.navidrome.enable = true;
      homelab.storage.enable = true;
      homelab.music.lyrics = {
        enable = true;
        libraryDir = "/nix/store/music";
      };
    }).config;
  invalidArtwork = (evaluate { homelab.music.artwork.enable = true; }).config;
  moonbase =
    (evaluate {
      services.jellyfin.enable = true;
      homelab.optional.jellyfinPlugins = {
        packages.Moonfin_nix = pkgs.hello;
        moonbase = {
          enable = true;
          seerrUrl = "http://127.0.0.1:5055";
        };
      };
    }).config;
  invalidMoonbase =
    (evaluate {
      services.jellyfin.enable = true;
      homelab.optional.jellyfinPlugins.moonbase = {
        enable = true;
        seerrUrl = "http://127.0.0.1:5055";
      };
    }).config;
  credentialUrl =
    (evaluate {
      services.jellyfin.enable = true;
      homelab.optional.jellyfinPlugins = {
        packages.Moonfin_nix = pkgs.hello;
        moonbase = {
          enable = true;
          seerrUrl = "http://fixture:password@127.0.0.1:5055";
        };
      };
    }).config;
  egress =
    (evaluate {
      homelab.networkPolicy = {
        directServices = [ "metadata" ];
        localOnlyServices = [ "subtitles" ];
      };
    }).config;
  invalidEgress =
    (evaluate {
      homelab.networkPolicy = {
        directServices = [ "metadata" ];
        localOnlyServices = [ "metadata" ];
      };
    }).config;
  rejected = cfg: lib.any (item: !item.assertion) cfg.assertions;
in
{
  defaultOptIn =
    empty.homelab.integration.webAuth == { }
    && !empty.homelab.music.lyrics.enable
    && !(builtins.hasAttr "music-lyrics" empty.systemd.services)
    && !empty.homelab.music.artwork.enable
    && !(builtins.hasAttr "music-artwork" empty.systemd.services);
  webAuthCredentialIsolation =
    webAuth.systemd.services.homelab-web-auth-sonarr.serviceConfig.LoadCredential == [
      "username:/run/credentials/sonarr-username"
      "password:/run/credentials/sonarr-password"
      "api-key:/run/credentials/sonarr-api-key"
    ]
    && webAuth.systemd.services.homelab-web-auth-sonarr.serviceConfig.StateDirectoryMode == "0700"
    && webAuth.systemd.services.homelab-web-auth-sonarr.serviceConfig.IPAddressDeny == [ "any" ];
  webAuthOrder =
    builtins.elem "sonarr.service" webAuth.systemd.services.homelab-web-auth-sonarr.requires
    && builtins.elem "homelab-integrate-sonarr.service" webAuth.systemd.services.homelab-web-auth-sonarr.after;
  webAuthNamedInstance =
    alias.homelab.integration.webAuth.sonarr-anime.apiVersion == "v3"
    && alias.systemd.services.homelab-web-auth-sonarr-anime.requires == [ "sonarr-anime.service" ];
  rejectsStoreCredentials = rejected invalidWebAuth;
  artworkConfigurable =
    artwork.systemd.services.music-artwork.unitConfig.RequiresMountsFor == [ "/srv/media/music" ]
    && builtins.elem "/srv/media/music" artwork.systemd.services.music-artwork.serviceConfig.ReadWritePaths
    && artwork.systemd.timers.music-artwork.timerConfig.OnUnitActiveSec == "12h"
    && artwork.systemd.services.music-artwork.serviceConfig.StateDirectoryMode == "0700";
  lyricsConfined =
    lyrics.systemd.services.music-lyrics.serviceConfig.ReadWritePaths == [ "/srv/media/library/music" ]
    && lyrics.systemd.services.music-lyrics.serviceConfig.ReadOnlyPaths == [ "/var/lib/navidrome" ]
    && lyrics.systemd.services.music-lyrics.serviceConfig.NoNewPrivileges
    && lyrics.systemd.services.music-lyrics.serviceConfig.StateDirectoryMode == "0700";
  lyricsRejectsMissingServices = rejected invalidLyrics;
  lyricsRejectsStorePath = rejected invalidLyricsPath;
  artworkRequiresNavidrome = rejected invalidArtwork;
  moonbaseDeclarative =
    lib.hasInfix "configure-moonbase" moonbase.systemd.services.jellyfin.preStart
    && lib.hasInfix "http://127.0.0.1:5055" moonbase.systemd.services.jellyfin.preStart;
  moonbaseRequiresPlugin = rejected invalidMoonbase;
  moonbaseRejectsCredentialUrl = rejected credentialUrl;
  directEgressExcludesPrivateRanges =
    builtins.elem "10.0.0.0/8" egress.systemd.services.metadata.serviceConfig.IPAddressDeny
    && builtins.elem "127.0.0.0/8" egress.systemd.services.metadata.serviceConfig.IPAddressAllow;
  localEgressBlocksHostDns =
    egress.systemd.services.subtitles.serviceConfig.IPAddressDeny == [ "any" ]
    && builtins.length egress.systemd.services.subtitles.serviceConfig.BindReadOnlyPaths == 2
    && builtins.elem "-/run/systemd/resolve/io.systemd.Resolve" egress.systemd.services.subtitles.serviceConfig.InaccessiblePaths;
  egressRoutesAreExclusive = rejected invalidEgress;
}
