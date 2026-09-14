{ evaluate, lib }:
let
  base = {
    homelab.integrations.jellyfin = {
      url = "http://127.0.0.1:8096";
      apiKeyFile = "/run/secrets/jellyfin-api";
      mode = "managed";
      administrator.passwordFile = "/run/secrets/jellyfin-admin-password";
      encoding = {
        threadCount = 2;
        enableThrottling = true;
      };
      libraries = {
        Movies = {
          collectionType = "movies";
          paths = [ "/srv/media/library/movies" ];
          enableRealtimeMonitor = true;
        };
        Television = {
          collectionType = "tvshows";
          paths = [ "/srv/media/library/tv" ];
        };
      };
      users.viewer.passwordFile = "/run/secrets/jellyfin-viewer-password";
    };
  };
  configured = (evaluate base).config;
  service = configured.homelab.integration.services.jellyfin;
  rejected =
    extra:
    lib.any (assertion: !assertion.assertion)
      (evaluate (lib.recursiveUpdate base extra)).config.assertions;
in
{
  enablesSharedReconciler = configured.homelab.integration.enable;
  typedLibraries =
    service.settings.libraries.Movies.collectionType == "movies"
    && service.settings.libraries.Movies.paths == [ "/srv/media/library/movies" ]
    && service.settings.libraries.Movies.options.EnableRealtimeMonitor
    && service.settings.libraries.Television.options == { };
  restrictiveUserDefaults =
    !service.settings.users.viewer.policy.IsAdministrator
    && service.settings.users.viewer.policy.IsHidden
    && !service.settings.users.viewer.policy.EnableAllFolders
    && service.settings.users.viewer.policy.EnableMediaPlayback
    && !service.settings.users.viewer.policy.EnableAudioPlaybackTranscoding
    && !service.settings.users.viewer.policy.EnableVideoPlaybackTranscoding
    && service.settings.users.viewer.policy.EnablePlaybackRemuxing
    && !service.settings.users.viewer.policy.EnableContentDeletion
    && !service.settings.users.viewer.policy.EnableContentDownloading
    && !service.settings.users.viewer.policy.EnableRemoteAccess;
  runtimeCredentials =
    service.apiKeyFile == "/run/secrets/jellyfin-api"
    && service.settings.login.password._secret == "/run/secrets/jellyfin-admin-password"
    && service.settings.users.viewer.password._secret == "/run/secrets/jellyfin-viewer-password";
  typedEncoding =
    service.settings.encoding.EncodingThreadCount == 2
    && service.settings.encoding.EnableThrottling
    && !(service.settings.encoding ? HardwareAccelerationType);
  duplicateLibraryPathRejected = rejected {
    homelab.integrations.jellyfin.libraries.Television.paths = [ "/srv/media/library/movies" ];
  };
  administratorCollisionRejected = rejected {
    homelab.integrations.jellyfin.users.admin.passwordFile = "/run/secrets/other-password";
  };
  storeSecretRejected = rejected {
    homelab.integrations.jellyfin.users.viewer.passwordFile = "/nix/store/public-invalid";
  };
}
