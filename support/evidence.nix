let
  record =
    {
      runtime ? [ ],
      integration ? [ ],
      workflow ? [ ],
      recovery ? [ ],
      vpn ? [ ],
      aarch64Runtime ? [ ],
    }:
    {
      configuration = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      runtimeTests = runtime;
      integrationTests = integration;
      workflowTests = workflow;
      recoveryTests = recovery;
      vpnTests = vpn;
      aarch64RuntimeTests = aarch64Runtime;
      tier = if runtime == [ ] then "evaluation" else "runtime-tested";
    };
in
{
  core = {
    sonarr = record {
      runtime = [ "media-runtime" ];
      integration = [ "integration-behavior" ];
    };
    radarr = record {
      runtime = [ "media-workflow" ];
      integration = [ "media-workflow" ];
      workflow = [ "media-workflow" ];
      recovery = [ "media-workflow" ];
    };
    lidarr = record {
      runtime = [ "arr-integration" ];
      integration = [ "arr-integration" ];
    };
    bazarr = record {
      runtime = [ "arr-integration" ];
      integration = [ "arr-integration" ];
    };
    prowlarr = record {
      runtime = [ "vpn-namespace" ];
      integration = [ "integration-behavior" ];
      vpn = [ "vpn-namespace" ];
    };
    seerr = record {
      runtime = [ "media-workflow" ];
      integration = [ "media-workflow" ];
      workflow = [ "media-workflow" ];
      recovery = [ "media-workflow" ];
    };
    qbittorrent = record {
      runtime = [
        "media-runtime"
        "media-workflow"
        "vpn-namespace"
      ];
      workflow = [ "media-workflow" ];
      vpn = [ "vpn-namespace" ];
    };
    sabnzbd = record {
      runtime = [
        "usenet-credentials"
        "vpn-namespace"
      ];
      vpn = [ "vpn-namespace" ];
    };
    nzbget = record {
      runtime = [
        "usenet-credentials"
        "vpn-namespace"
      ];
      vpn = [ "vpn-namespace" ];
      aarch64Runtime = [ "storage-missing" ];
    };
    jellyfin = record {
      runtime = [
        "media-runtime"
        "media-workflow"
      ];
      integration = [ "media-workflow" ];
      workflow = [ "media-workflow" ];
      recovery = [ "media-workflow" ];
    };
    plex = record { runtime = [ "media-runtime" ]; };
    navidrome = record {
      runtime = [ "audio-runtime" ];
      integration = [ "audio-runtime" ];
      aarch64Runtime = [ "storage-missing" ];
    };
    audiobookshelf = record {
      runtime = [ "audio-runtime" ];
      integration = [ "audio-runtime" ];
    };
  };

  optional = {
    autobrr = record {
      runtime = [ "autobrr" ];
      integration = [ "autobrr" ];
    };
    cross-seed = record {
      runtime = [ "cross-seed" ];
      workflow = [ "cross-seed" ];
    };
    unpackerr = record { runtime = [ "optional-media" ]; };
    flaresolverr = record { };
    komga = record {
      runtime = [ "books" ];
      workflow = [ "books" ];
    };
    kavita = record { };
    shelfmark = record { };
    pinchflat = record { };
    immich = record {
      runtime = [ "private-archives" ];
      recovery = [ "private-archives" ];
    };
    paperless = record {
      runtime = [ "private-archives" ];
      recovery = [ "private-archives" ];
    };
    syncthing = record { runtime = [ "optional-media" ]; };
    adguardhome = record { };
    scrutiny = record { };
    karakeep = record { runtime = [ "karakeep" ]; };
    maintainerr = record { runtime = [ "maintainerr" ]; };
  };
}
