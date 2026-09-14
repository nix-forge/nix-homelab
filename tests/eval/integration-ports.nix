{
  evaluate,
  pkgs,
  lib,
}:
let
  configured =
    (evaluate {
      imports = [
        ../../examples/integrated-media.nix
        ../../examples/optional-services.nix
      ];
      homelab.optional.apps = {
        unpackerr.enable = true;
        shelfmark.enable = true;
      };
      homelab.apps.qbittorrent.vpn.enable = false;
      services = {
        sonarr.settings.server = {
          port = 18989;
          urlbase = "/series/";
        };
        radarr.settings.server = {
          port = 17878;
          urlbase = "/movies";
        };
        lidarr.settings.server = {
          port = 18686;
          urlbase = "/audio";
        };
        prowlarr.settings.server = {
          port = 19696;
          urlbase = "/indexers";
        };
        seerr.port = 15055;
        bazarr.listenPort = 16767;
      };
    }).config;
  jobs = configured.homelab.integration.services;
  prowlarrResource =
    name: lib.findFirst (resource: (resource.match.name or null) == name) null jobs.prowlarr.resources;
  withUsenet =
    (evaluate {
      imports = [
        ../../examples/integrated-media.nix
        ../../examples/usenet.nix
      ];
      homelab.apps = {
        qbittorrent.vpn.enable = false;
        sabnzbd.enable = true;
        nzbget.enable = true;
      };
    }).config.homelab.integration.services;
  confinedPorts =
    (evaluate {
      homelab.apps.prowlarr = {
        enable = true;
        vpn.enable = true;
      };
      services.prowlarr.settings.server.port = 19696;
    }).config.homelab.vpn.namespace.hostIngressPorts.tcp;
  contracts = {
    confinedNativePort = builtins.elem 19696 confinedPorts && !(builtins.elem 9696 confinedPorts);
    managerPortsAndBases =
      jobs.sonarr.url == "http://127.0.0.1:18989/series"
      && jobs.radarr.url == "http://127.0.0.1:17878/movies"
      && jobs.lidarr.url == "http://127.0.0.1:18686/audio";
    managerPolicies =
      jobs.sonarr.settings.naming.renameEpisodes
      && jobs.radarr.settings.naming.renameMovies
      && jobs.lidarr.settings.naming.renameTracks
      && jobs.radarr.settings.mediaManagement.minimumFreeSpaceWhenImporting == 20480
      && jobs.radarr.settings.mediaManagement.recycleBinCleanupDays == 30;
    optionalDownloaders =
      lib.any (resource: (resource.match.name or null) == "SABnzbd") withUsenet.sonarr.resources
      && lib.any (resource: (resource.match.name or null) == "NZBGet") withUsenet.sonarr.resources
      && lib.any (resource: (resource.match.name or null) == "SABnzbd") withUsenet.radarr.resources
      && lib.any (resource: (resource.match.name or null) == "NZBGet") withUsenet.lidarr.resources;
    prowlarrConnections =
      jobs.prowlarr.url == "http://127.0.0.1:19696/indexers"
      && (prowlarrResource "sonarr").values.fields.prowlarrUrl == jobs.prowlarr.url
      && (prowlarrResource "sonarr").values.fields.baseUrl == jobs.sonarr.url
      && (prowlarrResource "radarr").values.fields.baseUrl == jobs.radarr.url;
    requestConnections =
      jobs.seerr.url == "http://127.0.0.1:15055"
      && jobs.seerr.settings.radarr.movies.port == 17878
      && jobs.seerr.settings.radarr.movies.baseUrl == "/movies"
      && jobs.seerr.settings.sonarr.television.port == 18989
      && jobs.seerr.settings.sonarr.television.baseUrl == "/series";
    subtitleConnections =
      jobs.bazarr.url == "http://127.0.0.1:16767"
      && jobs.bazarr.settings.sonarr.port == 18989
      && jobs.bazarr.settings.sonarr.base_url == "/series"
      && jobs.bazarr.settings.radarr.port == 17878
      && jobs.bazarr.settings.radarr.base_url == "/movies";
    optionalConnections =
      (builtins.head configured.services.unpackerr.settings.sonarr).url == jobs.sonarr.url
      && (builtins.head configured.services.unpackerr.settings.radarr).url == jobs.radarr.url
      && configured.services.shelfmark.environment.PROWLARR_URL == jobs.prowlarr.url;
    qualityConnections =
      configured.services.recyclarr.configuration.sonarr.homelab-sonarr.base_url == jobs.sonarr.url
      && configured.services.recyclarr.configuration.radarr.homelab-radarr.base_url == jobs.radarr.url;
  };
in
assert lib.all (value: value) (lib.attrValues contracts);
pkgs.writeText "integration-native-port-contracts.json" (
  builtins.toJSON {
    inherit contracts;
    evaluatedSystem = builtins.unsafeDiscardStringContext configured.system.build.toplevel.drvPath;
  }
)
