{ evaluate, lib }:
let
  base = {
    homelab.integrations = {
      jellyfin = {
        url = "http://127.0.0.1:8096";
        apiKeyFile = "/run/secrets/jellyfin-api";
        administrator.passwordFile = "/run/secrets/jellyfin-admin-password";
      };
      servarr.movies = {
        kind = "radarr";
        url = "http://127.0.0.1:7878/movies";
        apiKeyFile = "/run/secrets/radarr-api";
        rootFolders.main.path = "/srv/media/library/movies";
      };
      seerr = {
        url = "http://127.0.0.1:5055";
        jellyfin = {
          email = "admin@example.invalid";
          libraries = [ "Movies" ];
        };
        destinations.movies = {
          manager = "movies";
          rootFolder = "main";
          qualityProfile = "HD";
          isDefault = true;
        };
        quotas.movie = {
          limit = 5;
          days = 7;
        };
      };
    };
  };
  configured = (evaluate base).config;
  service = configured.homelab.integration.services.seerr;
  externalService =
    (evaluate (
      lib.recursiveUpdate base {
        homelab.integrations.seerr.jellyfin.externalUrl = "https://jellyfin.example.invalid";
      }
    )).config.homelab.integration.services.seerr;
  rejected =
    extra:
    lib.any (assertion: !assertion.assertion)
      (evaluate (lib.recursiveUpdate base extra)).config.assertions;
in
{
  sealedIdentities =
    let
      service =
        (evaluate (
          lib.recursiveUpdate base {
            homelab.integrations.jellyfin.administrator.usernameFile = "/run/secrets/admin-name";
            homelab.integrations.seerr = {
              mode = "managed";
              allowAutomaticRequests = true;
              jellyfin.emailFile = "/run/secrets/admin-email";
              autoApproveUsers = [ { _secret = "/run/secrets/viewer-name"; } ];
            };
          }
        )).config.homelab.integration.services.seerr;
    in
    service.settings.login.username._secret == "/run/secrets/admin-name"
    && service.settings.login.email._secret == "/run/secrets/admin-email"
    && (builtins.head service.settings.autoApproveUsers)._secret == "/run/secrets/viewer-name";
  typedDestination =
    service.settings.radarr.movies.hostname == "127.0.0.1"
    && service.settings.radarr.movies.port == 7878
    && service.settings.radarr.movies.baseUrl == "/movies"
    && service.settings.radarr.movies.activeDirectory == "/srv/media/library/movies"
    && service.settings.radarr.movies.apiKey._secret == "/run/secrets/radarr-api";
  conservativePermissions = service.settings.main.defaultPermissions == 32;
  typedQuota =
    service.settings.main.defaultQuotas.movie == {
      quotaLimit = 5;
      quotaDays = 7;
    };
  derivesJellyfinLogin =
    service.settings.login.username == "admin"
    && service.settings.login.password._secret == "/run/secrets/jellyfin-admin-password";
  externalJellyfinLink =
    !(service.settings ? jellyfin)
    && externalService.settings.jellyfin.externalHostname == "https://jellyfin.example.invalid"
    && externalService.settings.login.hostname == "127.0.0.1"
    && externalService.settings.login.useSsl == false;
  unknownManagerRejected = rejected {
    homelab.integrations.seerr.destinations.movies.manager = "missing";
  };
  autoApprovalRejected = rejected {
    homelab.integrations.seerr.defaultPermissions = [
      "request"
      "autoApprove"
    ];
  };
  autoApprovalRequiresExplicitGate =
    !rejected {
      homelab.integrations.seerr = {
        allowAutomaticRequests = true;
        defaultPermissions = [
          "request"
          "autoApprove"
        ];
      };
    };
  managedApprovalAllowlist =
    let
      selected =
        (evaluate (
          lib.recursiveUpdate base {
            homelab.integrations.seerr = {
              mode = "managed";
              allowAutomaticRequests = true;
              autoApproveUsers = [
                "admin"
                "viewer"
              ];
            };
          }
        )).config.homelab.integration.services.seerr;
    in
    selected.settings.autoApproveUsers == [
      "admin"
      "viewer"
    ]
    && selected.settings.main.defaultPermissions == 32;
  approvalAllowlistRequiresExplicitGate = rejected {
    homelab.integrations.seerr = {
      mode = "managed";
      autoApproveUsers = [ "viewer" ];
    };
  };
}
