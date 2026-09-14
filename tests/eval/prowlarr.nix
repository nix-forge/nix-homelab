{ evaluate, lib }:
let
  base = {
    homelab.integrations = {
      servarr.television = {
        kind = "sonarr";
        url = "http://127.0.0.1:8989";
        apiKeyFile = "/run/secrets/sonarr-api";
      };
      prowlarr = {
        url = "http://127.0.0.1:9696";
        apiKeyFile = "/run/secrets/prowlarr-api";
        mode = "managed";
        applications.television = { };
        proxies.vpn = {
          type = "socks5";
          tags = [ "vpn" ];
          host = "127.0.0.1";
          port = 1080;
          username = "prowlarr";
          passwordFile = "/run/secrets/proxy-password";
        };
        indexers.example = {
          implementation = "Cardigann";
          tags = [ "torrent" ];
          fields.baseUrl = "https://indexer.example.invalid";
          secretFields.definitionFile = "/run/secrets/example-definition";
        };
      };
    };
  };
  configured = (evaluate base).config;
  service = configured.homelab.integration.services.prowlarr;
  vpnTagResource = builtins.elemAt service.resources 0;
  torrentTagResource = builtins.elemAt service.resources 1;
  applicationResource = builtins.elemAt service.resources 2;
  proxyResource = builtins.elemAt service.resources 3;
  indexerResource = builtins.elemAt service.resources 4;
  rejected =
    extra:
    lib.any (assertion: !assertion.assertion)
      (evaluate (lib.recursiveUpdate base extra)).config.assertions;
in
{
  enablesSharedReconciler = configured.homelab.integration.enable;
  typedApplicationReference =
    applicationResource.endpoint == "applications"
    && applicationResource.match.name == "television"
    && applicationResource.values.implementation == "Sonarr"
    && applicationResource.values.syncLevel == "fullSync"
    && applicationResource.values.fields.baseUrl == "http://127.0.0.1:8989"
    && applicationResource.values.fields.apiKey._secret == "/run/secrets/sonarr-api"
    &&
      applicationResource.values.fields.syncCategories == [
        5000
        5010
        5020
        5030
        5040
        5045
        5050
        5090
      ];
  ownsNamedTags =
    vpnTagResource.match.label == "vpn"
    && torrentTagResource.match.label == "torrent"
    && vpnTagResource.endpoint == "tag"
    && torrentTagResource.endpoint == "tag";
  typedSocksProxy =
    proxyResource.endpoint == "indexerproxy"
    && proxyResource.match.name == "vpn"
    && proxyResource.values.implementation == "Socks5"
    &&
      proxyResource.values.tags == [
        {
          _lookup = {
            endpoint = "tag";
            name = "vpn";
          };
        }
      ]
    && proxyResource.values.fields.host == "127.0.0.1"
    && proxyResource.values.fields.port == 1080
    && proxyResource.values.fields.username == "prowlarr"
    && proxyResource.values.fields.password._secret == "/run/secrets/proxy-password";
  keepsProviderSecretsAtRuntime =
    indexerResource.endpoint == "indexer"
    && indexerResource.values.fields.baseUrl == "https://indexer.example.invalid"
    && indexerResource.values.fields.definitionFile._secret == "/run/secrets/example-definition";
  ordersAfterReferencedManagers = service.after == [ "homelab-integrate-television.service" ];
  unknownManagerRejected = rejected {
    homelab.integrations.prowlarr.applications.television.manager = "missing";
  };
  partialHttpAuthRejected = rejected {
    homelab.integrations.prowlarr.applications.television.authUsername = "user";
  };
  partialProxyAuthRejected = rejected {
    homelab.integrations.prowlarr.proxies.vpn.passwordFile = null;
  };
  invalidProxyShapeRejected = rejected {
    homelab.integrations.prowlarr.proxies.vpn = {
      type = "flaresolverr";
      url = "http://127.0.0.1:8191";
    };
  };
  literalSensitiveIndexerFieldRejected = rejected {
    homelab.integrations.prowlarr.indexers.example.fields.passkey = "public-value";
  };
  storeSecretRejected = rejected {
    homelab.integrations.prowlarr.indexers.example.secretFields.definitionFile =
      "/nix/store/public-invalid";
  };
}
