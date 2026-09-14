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
  rejected =
    extra:
    lib.any (assertion: !assertion.assertion)
      (evaluate (lib.recursiveUpdate base extra)).config.assertions;
in
{
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
}
