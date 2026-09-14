{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.integrations.jellyfin;
  json = pkgs.formats.json { };
  pathType = types.strMatching "/[A-Za-z0-9_./ -]+";
  optional =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };
  compact = lib.filterAttrsRecursive (_: value: value != null);
  secret = path: { _secret = path; };
  libraryType = types.submodule {
    options = {
      collectionType = mkOption {
        type = types.enum [
          "books"
          "homevideos"
          "mixed"
          "movies"
          "music"
          "musicvideos"
          "photos"
          "tvshows"
        ];
        description = "Jellyfin content type used when the library is created.";
      };
      paths = mkOption {
        type = types.nonEmptyListOf pathType;
        description = "Absolute media locations owned by this named library.";
      };
      enableRealtimeMonitor = optional types.bool "Watch supported filesystems for library changes.";
      enableChapterImageExtraction = optional types.bool "Allow chapter-image extraction for this library.";
      extractChapterImagesDuringLibraryScan = optional types.bool "Extract chapter images during full scans.";
      enableTrickplayImageExtraction = optional types.bool "Allow trickplay image generation for this library.";
      extractTrickplayImagesDuringLibraryScan = optional types.bool "Generate trickplay images during full scans.";
      saveTrickplayWithMedia = optional types.bool "Store trickplay data beside media rather than only in Jellyfin state.";
      extraOptions = mkOption {
        inherit (json) type;
        default = { };
        description = "Version-specific Jellyfin LibraryOptions outside the stable typed interface.";
      };
    };
  };
  userType = types.submodule {
    options = {
      passwordFile = mkOption {
        type = pathType;
        description = "Runtime file containing this user's desired password.";
      };
      isAdministrator = mkOption {
        type = types.bool;
        default = false;
        description = "Grant Jellyfin administrator privileges.";
      };
      isHidden = mkOption {
        type = types.bool;
        default = true;
        description = "Hide this account from the login screen.";
      };
      enableAllFolders = mkOption {
        type = types.bool;
        default = false;
        description = "Grant access to every library, including libraries created outside this module.";
      };
      enableMediaPlayback = mkOption {
        type = types.bool;
        default = true;
        description = "Allow local media playback.";
      };
      enableAudioPlaybackTranscoding = mkOption {
        type = types.bool;
        default = false;
        description = "Allow server-side audio transcoding for this user.";
      };
      enableVideoPlaybackTranscoding = mkOption {
        type = types.bool;
        default = false;
        description = "Allow server-side video transcoding for this user.";
      };
      enablePlaybackRemuxing = mkOption {
        type = types.bool;
        default = true;
        description = "Allow container remuxing without re-encoding media.";
      };
      enableContentDeletion = mkOption {
        type = types.bool;
        default = false;
        description = "Allow this user to delete media from storage.";
      };
      enableContentDownloading = mkOption {
        type = types.bool;
        default = false;
        description = "Allow this user to download original media files.";
      };
      enableRemoteAccess = mkOption {
        type = types.bool;
        default = false;
        description = "Allow authentication from outside Jellyfin's local-network classification.";
      };
      extraPolicy = mkOption {
        inherit (json) type;
        default = { };
        description = "Version-specific Jellyfin UserPolicy fields outside the stable typed interface.";
      };
    };
  };
  encodingType = types.submodule {
    options = {
      threadCount = optional types.int "FFmpeg encoding thread count; -1 lets Jellyfin choose.";
      enableThrottling = optional types.bool "Throttle transcodes that are sufficiently ahead of playback.";
      enableSegmentDeletion = optional types.bool "Delete old transcoding segments during playback.";
      segmentKeepSeconds = optional types.ints.positive "Seconds of completed segments retained behind playback.";
      hardwareAccelerationType = optional types.str "Jellyfin hardware acceleration backend selected by the host.";
      hardwareDecodingCodecs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Codecs explicitly allowed for hardware decoding; an empty list leaves the API value unmanaged.";
      };
      extraSettings = mkOption {
        inherit (json) type;
        default = { };
        description = "Version-specific encoding settings outside the stable typed interface.";
      };
    };
  };
  jellyfinType = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = "Jellyfin API base URL.";
      };
      apiKeyFile = mkOption {
        type = pathType;
        description = "Runtime API-key file used after attended bootstrap.";
      };
      mode = mkOption {
        type = types.enum [
          "bootstrap"
          "managed"
        ];
        default = "bootstrap";
        description = "Bootstrap preserves existing objects; managed updates fields owned by this declaration.";
      };
      after = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional prerequisite units for Jellyfin reconciliation.";
      };
      administrator = {
        name = mkOption {
          type = types.str;
          default = "admin";
          description = "Administrator name used for first-run setup and optional password rotation.";
        };
        passwordFile = mkOption {
          type = pathType;
          description = "Runtime file containing the administrator password.";
        };
      };
      startup = {
        serverName = mkOption {
          type = types.str;
          default = "Media library";
          description = "Server name installed during first-run setup.";
        };
        uiCulture = mkOption {
          type = types.str;
          default = "en";
          description = "UI culture installed during first-run setup.";
        };
        metadataCountryCode = mkOption {
          type = types.str;
          default = "US";
          description = "Metadata country installed during first-run setup.";
        };
        preferredMetadataLanguage = mkOption {
          type = types.str;
          default = "en";
          description = "Metadata language installed during first-run setup.";
        };
      };
      encoding = mkOption {
        type = encodingType;
        default = { };
        description = "Portable encoding policy; device access and packages remain native service settings.";
      };
      libraries = mkOption {
        type = types.attrsOf libraryType;
        default = { };
        description = "Named Jellyfin libraries updated without deleting undeclared libraries.";
      };
      users = mkOption {
        type = types.attrsOf userType;
        default = { };
        description = "Named local Jellyfin users with restrictive policy defaults.";
      };
      extraSettings = mkOption {
        inherit (json) type;
        default = { };
        description = "Version-specific top-level reconciler settings outside the stable typed interface.";
      };
    };
  };
  libraryOptions =
    library:
    compact {
      EnableRealtimeMonitor = library.enableRealtimeMonitor;
      EnableChapterImageExtraction = library.enableChapterImageExtraction;
      ExtractChapterImagesDuringLibraryScan = library.extractChapterImagesDuringLibraryScan;
      EnableTrickplayImageExtraction = library.enableTrickplayImageExtraction;
      ExtractTrickplayImagesDuringLibraryScan = library.extractTrickplayImagesDuringLibraryScan;
      SaveTrickplayWithMedia = library.saveTrickplayWithMedia;
    }
    // library.extraOptions;
  library = item: {
    inherit (item) collectionType paths;
    options = libraryOptions item;
  };
  user = item: {
    password = secret item.passwordFile;
    policy = {
      IsAdministrator = item.isAdministrator;
      IsHidden = item.isHidden;
      EnableAllFolders = item.enableAllFolders;
      EnableMediaPlayback = item.enableMediaPlayback;
      EnableAudioPlaybackTranscoding = item.enableAudioPlaybackTranscoding;
      EnableVideoPlaybackTranscoding = item.enableVideoPlaybackTranscoding;
      EnablePlaybackRemuxing = item.enablePlaybackRemuxing;
      EnableContentDeletion = item.enableContentDeletion;
      EnableContentDownloading = item.enableContentDownloading;
      EnableRemoteAccess = item.enableRemoteAccess;
    }
    // item.extraPolicy;
  };
  encoding =
    compact {
      EncodingThreadCount = cfg.encoding.threadCount;
      EnableThrottling = cfg.encoding.enableThrottling;
      EnableSegmentDeletion = cfg.encoding.enableSegmentDeletion;
      SegmentKeepSeconds = cfg.encoding.segmentKeepSeconds;
      HardwareAccelerationType = cfg.encoding.hardwareAccelerationType;
      HardwareDecodingCodecs =
        if cfg.encoding.hardwareDecodingCodecs == [ ] then null else cfg.encoding.hardwareDecodingCodecs;
    }
    // cfg.encoding.extraSettings;
  runtimePath = path: lib.hasPrefix "/" path && !(lib.hasPrefix "/nix/store" path);
  libraryPaths = lib.concatMap (item: item.paths) (lib.attrValues cfg.libraries);
  secretPaths = [
    cfg.apiKeyFile
    cfg.administrator.passwordFile
  ]
  ++ map (item: item.passwordFile) (lib.attrValues cfg.users);
in
{
  options.homelab.integrations.jellyfin = mkOption {
    type = types.nullOr jellyfinType;
    default = null;
    description = "Typed Jellyfin bootstrap, library, encoding and restricted-user reconciliation.";
  };

  config = lib.mkIf (cfg != null) {
    homelab.integration.enable = lib.mkDefault true;
    homelab.integration.services.jellyfin = {
      kind = "jellyfin";
      inherit (cfg)
        url
        apiKeyFile
        mode
        after
        ;
      settings = lib.recursiveUpdate {
        startup = {
          ServerName = cfg.startup.serverName;
          UICulture = cfg.startup.uiCulture;
          MetadataCountryCode = cfg.startup.metadataCountryCode;
          PreferredMetadataLanguage = cfg.startup.preferredMetadataLanguage;
        };
        login = {
          username = cfg.administrator.name;
          password = secret cfg.administrator.passwordFile;
        };
        inherit encoding;
        libraries = lib.mapAttrs (_: library) cfg.libraries;
        users = lib.mapAttrs (_: user) cfg.users;
      } cfg.extraSettings;
    };
    assertions = [
      {
        assertion = lib.all runtimePath secretPaths;
        message = "Jellyfin integration credentials must be absolute runtime paths outside the Nix store.";
      }
      {
        assertion = builtins.length libraryPaths == builtins.length (lib.unique libraryPaths);
        message = "A Jellyfin media path may be owned by only one declared library.";
      }
      {
        assertion = !(cfg.users ? ${cfg.administrator.name});
        message = "The Jellyfin administrator is managed by the dedicated administrator declaration, not users.";
      }
    ];
  };
}
