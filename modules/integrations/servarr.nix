{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.integrations;
  inherit (lib) mkOption types;
  json = pkgs.formats.json { };
  pathType = types.strMatching "/[A-Za-z0-9_./-]+";
  secret = path: { _secret = path; };
  compact = lib.filterAttrsRecursive (_: value: value != null);
  optional =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };
  downloadClientType = types.submodule (
    { name, ... }: {
      options = {
        type = mkOption {
          type = types.enum [
            "qbittorrent"
            "sabnzbd"
            "nzbget"
            "transmission"
            "deluge"
          ];
          description = "Download-client provider translated to the running Servarr schema.";
        };
        name = mkOption {
          type = types.str;
          default = name;
          description = "Stable display name used to own this client in each manager.";
        };
        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Host name or address reachable from the manager.";
        };
        port = mkOption {
          type = types.port;
          description = "Download-client API port.";
        };
        useSsl = mkOption {
          type = types.bool;
          default = false;
          description = "Use TLS between the manager and download client.";
        };
        urlBase = mkOption {
          type = types.str;
          default = "";
          description = "Optional URL path used by the client's RPC interface.";
        };
        usernameFile = optional pathType "Runtime file containing the client username.";
        passwordFile = optional pathType "Runtime file containing the client password.";
        apiKeyFile = optional pathType "Runtime file containing the client API key.";
        after = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Units that must complete before managers reconcile this client.";
        };
        manageCategories = mkOption {
          type = types.bool;
          default = false;
          description = "Create referenced categories in the local qBittorrent service before manager reconciliation.";
        };
        extraFields = mkOption {
          inherit (json) type;
          default = { };
          description = "Schema-checked provider fields not covered by the stable typed interface.";
        };
      };
    }
  );
  clientReferenceType = types.submodule (
    { name, ... }: {
      options = {
        client = mkOption {
          type = types.str;
          default = name;
          description = "Name of a declaration in homelab.integrations.downloadClients.";
        };
        category = mkOption {
          type = types.strMatching "[A-Za-z0-9][A-Za-z0-9._/-]*";
          description = "Unique queue category for this manager workflow.";
        };
        savePath = optional pathType "Local qBittorrent category path; defaults below the shared torrent root.";
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether the manager may send jobs to this client.";
        };
        priority = mkOption {
          type = types.ints.between 1 50;
          default = 1;
          description = "Manager-side client priority; lower values are preferred.";
        };
        removeCompletedDownloads = mkOption {
          type = types.bool;
          default = false;
          description = "Allow the manager to remove completed client jobs.";
        };
        removeFailedDownloads = mkOption {
          type = types.bool;
          default = false;
          description = "Allow the manager to remove failed client jobs.";
        };
      };
    }
  );
  notificationEventsType = types.submodule {
    options = {
      onGrab = mkOption {
        type = types.bool;
        default = false;
        description = "Notify when a release is grabbed.";
      };
      onDownload = mkOption {
        type = types.bool;
        default = true;
        description = "Notify after a download is imported.";
      };
      onUpgrade = mkOption {
        type = types.bool;
        default = true;
        description = "Include upgrades in download notifications.";
      };
      onImportComplete = mkOption {
        type = types.bool;
        default = true;
        description = "Notify after all files in an import complete.";
      };
      onRename = mkOption {
        type = types.bool;
        default = true;
        description = "Notify after files are renamed.";
      };
      onHealthIssue = mkOption {
        type = types.bool;
        default = true;
        description = "Notify when a manager health check fails.";
      };
      includeHealthWarnings = mkOption {
        type = types.bool;
        default = false;
        description = "Include warning-level manager health events.";
      };
      onHealthRestored = mkOption {
        type = types.bool;
        default = true;
        description = "Notify when a manager health check recovers.";
      };
      onApplicationUpdate = mkOption {
        type = types.bool;
        default = false;
        description = "Notify after the manager updates itself.";
      };
      onManualInteractionRequired = mkOption {
        type = types.bool;
        default = true;
        description = "Notify when an import requires operator intervention.";
      };
    };
  };
  notificationType = types.submodule (
    { name, ... }: {
      options = {
        type = mkOption {
          type = types.enum [
            "jellyfin"
            "ntfy"
          ];
          description = "Reviewed Servarr notification provider.";
        };
        name = mkOption {
          type = types.str;
          default = name;
          description = "Stable display name owned in each referencing manager.";
        };
        after = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Units that must be ready before managers reconcile this notification.";
        };
        tags = mkOption {
          type = types.listOf (types.strMatching "[A-Za-z0-9][A-Za-z0-9._ -]*");
          default = [ ];
          description = "Manager tags restricting this notification.";
        };
        events = mkOption {
          type = notificationEventsType;
          default = { };
          description = "Events that trigger this notification.";
        };
        host = optional types.str "Jellyfin host name or address.";
        port = optional types.port "Jellyfin API port.";
        useSsl = mkOption {
          type = types.bool;
          default = false;
          description = "Use TLS for the Jellyfin connection.";
        };
        urlBase = mkOption {
          type = types.str;
          default = "";
          description = "Optional Jellyfin URL base.";
        };
        apiKeyFile = optional pathType "Runtime file containing the Jellyfin API key.";
        notify = mkOption {
          type = types.bool;
          default = false;
          description = "Send Jellyfin user notifications as well as library updates.";
        };
        updateLibrary = mkOption {
          type = types.bool;
          default = true;
          description = "Tell Jellyfin to refresh affected library items.";
        };
        mapFrom = mkOption {
          type = types.str;
          default = "";
          description = "Optional manager path prefix translated for Jellyfin.";
        };
        mapTo = mkOption {
          type = types.str;
          default = "";
          description = "Optional Jellyfin path prefix paired with mapFrom.";
        };
        serverUrl = optional types.str "ntfy server URL; null uses the provider default.";
        accessTokenFile = optional pathType "Runtime file containing an ntfy access token.";
        username = optional types.str "Optional ntfy username.";
        passwordFile = optional pathType "Runtime file containing an ntfy password.";
        topics = mkOption {
          type = types.listOf (types.strMatching "[A-Za-z0-9_-]+");
          default = [ ];
          description = "ntfy topics receiving events.";
        };
        priority = mkOption {
          type = types.ints.between 1 5;
          default = 3;
          description = "ntfy message priority from 1 (minimum) through 5 (maximum).";
        };
        messageTags = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "ntfy message tags or emoji short names.";
        };
        clickUrl = mkOption {
          type = types.str;
          default = "";
          description = "Optional ntfy notification click target.";
        };
        extraFields = mkOption {
          inherit (json) type;
          default = { };
          description = "Schema-checked provider fields not covered by the stable typed interface.";
        };
      };
    }
  );
  rootFolderType = types.submodule {
    options = {
      path = mkOption {
        type = pathType;
        description = "Stable absolute library root registered with the manager.";
      };
      extraSettings = mkOption {
        inherit (json) type;
        default = { };
        description = "Schema-checked root fields, such as Lidarr's named profile lookups.";
      };
    };
  };
  downloadHandlingType = types.submodule {
    options = {
      enableCompletedDownloadHandling = optional types.bool "Import completed downloads automatically.";
      autoRedownloadFailed = optional types.bool "Automatically search again after a failed download.";
      autoRedownloadFailedFromInteractiveSearch = optional types.bool "Automatically search again after a failed interactive download.";
    };
  };
  mediaManagementType = types.submodule {
    options = {
      recycleBin = optional pathType "Directory receiving deleted or upgraded media.";
      recycleBinCleanupDays = optional types.ints.unsigned "Days to retain items in the recycle directory.";
      downloadPropersAndRepacks = optional (types.enum [
        "preferAndUpgrade"
        "doNotUpgrade"
        "doNotPrefer"
      ]) "Policy for proper and repack releases.";
      deleteEmptyFolders = optional types.bool "Remove empty library directories after import.";
      fileDate = optional types.str "Upstream file timestamp policy.";
      rescanAfterRefresh = optional (types.enum [
        "always"
        "afterManual"
        "never"
      ]) "When to rescan files after a metadata refresh.";
      setPermissionsLinux = optional types.bool "Let the manager chmod imported files.";
      chmodFolder = optional types.str "Permission mode used when permission management is enabled.";
      chownGroup = optional types.str "Group used when permission management is enabled.";
      skipFreeSpaceCheckWhenImporting = optional types.bool "Skip the import free-space guard.";
      minimumFreeSpaceWhenImporting = optional types.ints.unsigned "Minimum free space in MiB before import.";
      copyUsingHardlinks = optional types.bool "Prefer hardlinks when downloads and libraries share a filesystem.";
      useScriptImport = optional types.bool "Use an operator-supplied import script.";
      scriptImportPath = optional pathType "Absolute operator-supplied import script path.";
      importExtraFiles = optional types.bool "Import declared non-media file extensions.";
      extraFileExtensions = optional types.str "Comma-separated extra file extensions accepted by Servarr.";
      enableMediaInfo = optional types.bool "Read media information during imports.";
      autoUnmonitorPreviouslyDownloadedEpisodes = optional types.bool "Sonarr unmonitor policy.";
      createEmptySeriesFolders = optional types.bool "Sonarr empty-series-folder policy.";
      episodeTitleRequired = optional (types.enum [
        "always"
        "bulkSeasonReleases"
        "never"
      ]) "Sonarr episode-title requirement.";
      autoUnmonitorPreviouslyDownloadedMovies = optional types.bool "Radarr unmonitor policy.";
      createEmptyMovieFolders = optional types.bool "Radarr empty-movie-folder policy.";
      autoRenameFolders = optional types.bool "Radarr folder rename policy.";
      pathsDefaultStatic = optional types.bool "Radarr static-path default.";
      autoUnmonitorPreviouslyDownloadedTracks = optional types.bool "Lidarr unmonitor policy.";
      createEmptyArtistFolders = optional types.bool "Lidarr empty-artist-folder policy.";
      watchLibraryForChanges = optional types.bool "Lidarr library watcher policy.";
      allowFingerprinting = optional (types.enum [
        "allFiles"
        "newFiles"
        "never"
      ]) "Lidarr audio fingerprint policy.";
    };
  };
  namingType = types.submodule {
    options = {
      renameEpisodes = optional types.bool "Rename imported Sonarr episodes.";
      renameMovies = optional types.bool "Rename imported Radarr movies.";
      renameTracks = optional types.bool "Rename imported Lidarr tracks.";
      replaceIllegalCharacters = optional types.bool "Replace filesystem-invalid characters.";
      colonReplacementFormat = optional types.int "Upstream colon replacement style.";
      customColonReplacementFormat = optional types.str "Custom replacement used for colons.";
      multiEpisodeStyle = optional types.int "Sonarr multi-episode naming style.";
      standardEpisodeFormat = optional types.str "Sonarr standard episode template.";
      dailyEpisodeFormat = optional types.str "Sonarr daily episode template.";
      animeEpisodeFormat = optional types.str "Sonarr anime episode template.";
      seriesFolderFormat = optional types.str "Sonarr series directory template.";
      seasonFolderFormat = optional types.str "Sonarr season directory template.";
      specialsFolderFormat = optional types.str "Sonarr specials directory template.";
      standardMovieFormat = optional types.str "Radarr movie filename template.";
      movieFolderFormat = optional types.str "Radarr movie directory template.";
      standardTrackFormat = optional types.str "Lidarr track filename template.";
      multiDiscTrackFormat = optional types.str "Lidarr multidisc track template.";
      artistFolderFormat = optional types.str "Lidarr artist directory template.";
    };
  };
  instanceType = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "sonarr"
          "radarr"
          "lidarr"
        ];
        description = "Servarr application represented by this independently named instance.";
      };
      url = mkOption {
        type = types.str;
        description = "Loopback HTTP or remote HTTPS API base URL.";
      };
      apiKeyFile = mkOption {
        type = pathType;
        description = "Runtime API-key file for this instance.";
      };
      installApiKey = mkOption {
        type = types.bool;
        default = false;
        description = "Install this key into the one local native service of the same kind.";
      };
      mode = mkOption {
        type = types.enum [
          "bootstrap"
          "managed"
        ];
        default = "bootstrap";
        description = "Bootstrap preserves existing matches; managed updates declared fields. Neither deletes resources.";
      };
      after = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional prerequisite units for this instance.";
      };
      rootFolders = mkOption {
        type = types.attrsOf rootFolderType;
        default = { };
        description = "Named library roots, matched by their stable absolute paths.";
      };
      downloadClients = mkOption {
        type = types.attrsOf clientReferenceType;
        default = { };
        description = "References to reusable download-client declarations with unique categories.";
      };
      notifications = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Names from homelab.integrations.notifications reconciled into this instance.";
      };
      tags = mkOption {
        type = types.listOf (types.strMatching "[A-Za-z0-9][A-Za-z0-9._ -]*");
        default = [ ];
        description = "Manager tags to create if absent. Undeclared tags are preserved.";
      };
      settings = {
        downloadHandling = mkOption {
          type = downloadHandlingType;
          default = { };
          description = "Typed completed-download and retry policy.";
        };
        mediaManagement = mkOption {
          type = mediaManagementType;
          default = { };
          description = "Typed storage and import policy supported by the pinned managers.";
        };
        naming = mkOption {
          type = namingType;
          default = { };
          description = "Typed service-specific naming templates.";
        };
      };
      extraResources = mkOption {
        type = types.listOf json.type;
        default = [ ];
        description = "Unsupported schema-checked Arr resources for forward compatibility.";
      };
      extraSettings = mkOption {
        inherit (json) type;
        default = { };
        description = "Unsupported manager settings for forward compatibility.";
      };
    };
  };
  implementations = {
    qbittorrent = "QBittorrent";
    sabnzbd = "Sabnzbd";
    nzbget = "Nzbget";
    transmission = "Transmission";
    deluge = "Deluge";
  };
  categoryFields = {
    sonarr = "tvCategory";
    radarr = "movieCategory";
    lidarr = "musicCategory";
  };
  clientFields =
    client:
    compact {
      inherit (client)
        host
        port
        useSsl
        urlBase
        ;
      username = if client.usernameFile == null then null else secret client.usernameFile;
      password = if client.passwordFile == null then null else secret client.passwordFile;
      apiKey = if client.apiKeyFile == null then null else secret client.apiKeyFile;
    }
    // client.extraFields;
  downloadResource =
    instance: reference:
    let
      client = cfg.downloadClients.${reference.client};
    in
    {
      endpoint = "downloadclient";
      match.name = client.name;
      values = {
        implementation = implementations.${client.type};
        inherit (reference)
          enable
          priority
          removeCompletedDownloads
          removeFailedDownloads
          ;
        fields = clientFields client // {
          ${categoryFields.${instance.kind}} = reference.category;
        };
      };
    };
  notificationFields =
    notification:
    if notification.type == "jellyfin" then
      {
        inherit (notification)
          host
          port
          useSsl
          urlBase
          notify
          updateLibrary
          mapFrom
          mapTo
          ;
        apiKey = secret notification.apiKeyFile;
      }
      // notification.extraFields
    else
      compact {
        inherit (notification)
          serverUrl
          username
          topics
          priority
          clickUrl
          ;
        tags = notification.messageTags;
        accessToken =
          if notification.accessTokenFile == null then null else secret notification.accessTokenFile;
        password = if notification.passwordFile == null then null else secret notification.passwordFile;
      }
      // notification.extraFields;
  notificationResource = notification: {
    endpoint = "notification";
    match.name = notification.name;
    values = {
      implementation =
        {
          jellyfin = "MediaBrowser";
          ntfy = "Ntfy";
        }
        .${notification.type};
      tags = map (label: {
        _lookup = {
          endpoint = "tag";
          name = label;
        };
      }) notification.tags;
      fields = notificationFields notification;
    }
    // notification.events;
  };
  knownReferences =
    instance:
    lib.filterAttrs (_: value: cfg.downloadClients ? ${value.client}) instance.downloadClients;
  knownNotifications =
    instance: lib.filter (name: cfg.notifications ? ${name}) instance.notifications;
  resources =
    instance:
    (lib.mapAttrsToList (_: root: {
      endpoint = "rootfolder";
      match.path = root.path;
      values = root.extraSettings;
    }) instance.rootFolders)
    ++ (lib.mapAttrsToList (_: downloadResource instance) (knownReferences instance))
    ++ (map
      (label: {
        endpoint = "tag";
        match = { inherit label; };
        values = { };
      })
      (
        lib.unique (
          instance.tags ++ lib.concatMap (name: cfg.notifications.${name}.tags) (knownNotifications instance)
        )
      )
    )
    ++ (map (name: notificationResource cfg.notifications.${name}) (knownNotifications instance));
  instanceSettings =
    instance:
    compact {
      downloadHandling = compact instance.settings.downloadHandling;
      mediaManagement = compact instance.settings.mediaManagement;
      naming = compact instance.settings.naming;
    };
  service = instance: {
    inherit (instance)
      kind
      url
      apiKeyFile
      installApiKey
      mode
      extraResources
      extraSettings
      ;
    after = lib.unique (
      instance.after
      ++ lib.concatMap (reference: cfg.downloadClients.${reference.client}.after) (
        lib.attrValues (knownReferences instance)
      )
      ++ lib.concatMap (name: cfg.notifications.${name}.after) (knownNotifications instance)
      ++ lib.optional (lib.any (reference: cfg.downloadClients.${reference.client}.manageCategories) (
        lib.attrValues (knownReferences instance)
      )) "homelab-configure-qbittorrent.service"
    );
    resources = resources instance;
    settings = instanceSettings instance;
  };
  instances = lib.attrValues cfg.servarr;
  references = lib.concatMap (instance: lib.attrValues instance.downloadClients) instances;
  categoryAssignments = map (reference: "${reference.client}:${reference.category}") references;
  managedQbittorrentReferences = lib.concatMap (
    instance:
    lib.filter (
      reference:
      (cfg.downloadClients.${reference.client} or { manageCategories = false; }).manageCategories
    ) (lib.attrValues (knownReferences instance))
  ) instances;
  managedQbittorrentCategories = builtins.listToAttrs (
    map (reference: {
      name = reference.category;
      value.savePath =
        if reference.savePath == null then
          "${config.homelab.storage.downloadsDir}/torrents/${reference.category}"
        else
          reference.savePath;
    }) managedQbittorrentReferences
  );
  secretPaths =
    client:
    lib.filter (path: path != null) [
      client.usernameFile
      client.passwordFile
      client.apiKeyFile
    ];
  credentialShapeValid =
    client:
    if client.type == "qbittorrent" then
      client.usernameFile != null && client.passwordFile != null
    else if client.type == "sabnzbd" then
      client.apiKeyFile != null
    else if client.type == "nzbget" || client.type == "transmission" then
      client.usernameFile != null && client.passwordFile != null
    else
      client.passwordFile != null;
  notificationSecretPaths =
    notification:
    lib.filter (path: path != null) [
      notification.apiKeyFile
      notification.accessTokenFile
      notification.passwordFile
    ];
  runtimePath =
    path: lib.hasPrefix "/" path && !(lib.hasPrefix "/nix/store" path) && !(lib.hasInfix ":" path);
in
{
  options.homelab.integrations = {
    downloadClients = mkOption {
      type = types.attrsOf downloadClientType;
      default = { };
      description = "Reusable typed download-client connections referenced by Servarr instances.";
    };
    notifications = mkOption {
      type = types.attrsOf notificationType;
      default = { };
      description = "Reusable typed Jellyfin and ntfy notifications referenced by Servarr instances.";
    };
    servarr = mkOption {
      type = types.attrsOf instanceType;
      default = { };
      description = "Independently named Sonarr, Radarr and Lidarr API instances.";
    };
  };

  config = lib.mkIf (cfg.servarr != { }) {
    homelab.integration.enable = lib.mkDefault true;
    homelab.integration.services = lib.mapAttrs (_: service) cfg.servarr;
    homelab.apps.qbittorrent.configuration.categories = managedQbittorrentCategories;
    assertions = [
      {
        assertion = builtins.length categoryAssignments == builtins.length (lib.unique categoryAssignments);
        message = "Each Servarr download-client category must be unique per client across instance workflows.";
      }
    ]
    ++ lib.mapAttrsToList (name: client: {
      assertion =
        credentialShapeValid client
        && (
          !client.manageCategories
          || (
            client.type == "qbittorrent"
            && config.homelab.apps.qbittorrent.enable
            && client.host == config.homelab.apps.qbittorrent.bindAddress
            && client.port == config.homelab.apps.qbittorrent.webuiPort
            && !client.useSsl
          )
        )
        && lib.all runtimePath (secretPaths client);
      message = "Download client ${name} has invalid credentials, an unsafe secret path, or an invalid local category target.";
    }) cfg.downloadClients
    ++ lib.mapAttrsToList (name: notification: {
      assertion =
        builtins.length notification.tags == builtins.length (lib.unique notification.tags)
        && builtins.length notification.topics == builtins.length (lib.unique notification.topics)
        && (!notification.events.onUpgrade || notification.events.onDownload)
        && lib.all runtimePath (notificationSecretPaths notification)
        && (
          if notification.type == "jellyfin" then
            notification.host != null
            && notification.port != null
            && notification.apiKeyFile != null
            && notification.serverUrl == null
            && notification.accessTokenFile == null
            && notification.username == null
            && notification.passwordFile == null
            && (notification.mapFrom == "") == (notification.mapTo == "")
          else
            notification.host == null
            && notification.port == null
            && notification.apiKeyFile == null
            && notification.topics != [ ]
            && (
              if notification.accessTokenFile != null then
                notification.username == null && notification.passwordFile == null
              else
                (notification.username == null) == (notification.passwordFile == null)
            )
        );
      message = "Notification ${name} has invalid provider fields, credentials, event dependencies, or duplicate tags/topics.";
    }) cfg.notifications
    ++ lib.mapAttrsToList (name: instance: {
      assertion =
        !(lib.hasPrefix "/nix/store" instance.apiKeyFile)
        && lib.all (reference: cfg.downloadClients ? ${reference.client}) (
          lib.attrValues instance.downloadClients
        )
        && lib.all (notification: cfg.notifications ? ${notification}) instance.notifications
        && builtins.length instance.notifications == builtins.length (lib.unique instance.notifications)
        && builtins.length instance.tags == builtins.length (lib.unique instance.tags);
      message = "Servarr instance ${name} has an unsafe API key, unknown reference, or duplicate notification/tag.";
    }) cfg.servarr;
  };
}
