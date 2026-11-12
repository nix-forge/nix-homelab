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
      network = {
        knownProxies = [ "127.0.0.1" ];
        localNetworkAddresses = [ "127.0.0.1" ];
        localNetworkSubnets = [ "192.168.1.0/24" ];
        enableRemoteAccess = false;
        enableUPnP = false;
      };
      branding = {
        loginDisclaimer = "Private media library";
        splashscreenEnabled = false;
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
  passwordOnly =
    (evaluate {
      homelab.integrations.jellyfin = {
        url = "http://127.0.0.1:8096";
        administrator.passwordFile = "/run/secrets/jellyfin-admin-password";
      };
    }).config.homelab.integration.services.jellyfin;
  rejected =
    extra:
    lib.any (assertion: !assertion.assertion)
      (evaluate (lib.recursiveUpdate base extra)).config.assertions;
in
{
  sealedNames =
    let
      service =
        (evaluate (
          lib.recursiveUpdate base {
            homelab.integrations.jellyfin = {
              administrator.usernameFile = "/run/secrets/admin-name";
              users.viewer.nameFile = "/run/secrets/viewer-name";
            };
          }
        )).config.homelab.integration.services.jellyfin;
    in
    service.settings.login.username._secret == "/run/secrets/admin-name"
    && service.settings.users.viewer.name._secret == "/run/secrets/viewer-name";
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
  administratorLoginWithoutApiKey =
    passwordOnly.apiKeyFile == null
    && passwordOnly.settings.login.password._secret == "/run/secrets/jellyfin-admin-password";
  typedEncoding =
    service.settings.encoding.EncodingThreadCount == 2
    && service.settings.encoding.EnableThrottling
    && !(service.settings.encoding ? HardwareAccelerationType);
  typedNetwork =
    service.settings.network.KnownProxies == [ "127.0.0.1" ]
    && service.settings.network.LocalNetworkAddresses == [ "127.0.0.1" ]
    && service.settings.network.LocalNetworkSubnets == [ "192.168.1.0/24" ]
    && !service.settings.network.EnableRemoteAccess
    && !service.settings.network.EnableUPnP;
  typedBranding =
    service.settings.branding.LoginDisclaimer == "Private media library"
    && !service.settings.branding.SplashscreenEnabled
    && !(service.settings.branding ? CustomCss);
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
