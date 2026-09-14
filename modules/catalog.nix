# Internal service identity and policy classes. Native `services.*` options own
# application configuration; this catalog only removes duplicated module lists.
{
  core = {
    sonarr = {
      integration = "sonarr";
      hostManaged = true;
    };
    radarr = {
      integration = "radarr";
      hostManaged = true;
    };
    lidarr = {
      integration = "lidarr";
      hostManaged = true;
    };
    bazarr = {
      integration = "bazarr";
      hostManaged = true;
    };
    prowlarr = {
      integration = "prowlarr";
      hostManaged = true;
    };
    seerr = {
      integration = "seerr";
      hostManaged = true;
    };
    qbittorrent = {
      integration = null;
      hostManaged = true;
    };
    sabnzbd = {
      integration = null;
      hostManaged = true;
    };
    nzbget = {
      integration = null;
      hostManaged = true;
    };
    jellyfin = {
      integration = "jellyfin";
      hostManaged = true;
    };
    plex = {
      integration = null;
      hostManaged = true;
    };
    navidrome = {
      integration = "navidrome";
      hostManaged = true;
    };
    audiobookshelf = {
      integration = "audiobookshelf";
      hostManaged = true;
    };
  };

  optional = {
    autobrr = {
      integration = "autobrr";
      hostManaged = true;
    };
    cross-seed = {
      hostManaged = true;
      mediaAccess = "writer";
    };
    unpackerr = {
      hostManaged = true;
      mediaAccess = "writer";
    };
    flaresolverr.hostManaged = true;
    komga = {
      hostManaged = true;
      mediaAccess = "reader";
    };
    kavita = {
      hostManaged = true;
      mediaAccess = "reader";
    };
    shelfmark = {
      hostManaged = true;
      mediaAccess = "writer";
    };
    pinchflat = {
      hostManaged = true;
      mediaAccess = "writer";
    };
    immich.hostManaged = true;
    paperless.hostManaged = true;
    syncthing.hostManaged = true;
    adguardhome.hostManaged = true;
    scrutiny.hostManaged = true;
    karakeep.hostManaged = true;
    maintainerr = {
      hostManaged = true;
      nativeService = false;
    };
  };
}
