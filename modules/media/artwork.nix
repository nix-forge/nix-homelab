{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.music.artwork;
  navidrome = config.services.navidrome;
  dataDir = lib.attrByPath [ "DataFolder" ] "/var/lib/navidrome" navidrome.settings;
  cacheDir = lib.attrByPath [ "CacheFolder" ] "/var/cache/navidrome" navidrome.settings;
  navidromeConfig =
    (pkgs.formats.json { }).generate "music-artwork-navidrome.json"
      navidrome.settings;
  runtimePath = import ../lib/runtime-path.nix lib;
  syncArtwork = pkgs.writers.writePython3Bin "sync-music-artwork" {
    libraries = [ pkgs.python3Packages.pillow ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../../scripts/media/artwork.py);
in
{
  options.homelab.music.artwork = {
    enable = lib.mkEnableOption "canonical album artwork synchronization for Navidrome";
    libraryDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.homelab.storage.libraryDir}/music";
      description = "Writable music library whose album covers are maintained.";
    };
    databaseFile = lib.mkOption {
      type = lib.types.str;
      default = "${dataDir}/navidrome.db";
      description = "Navidrome SQLite database used to identify albums.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_-]+";
      default = "music-artwork";
      description = "Private systemd state directory for artwork receipts.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = navidrome.user;
      description = "User that owns the Navidrome library and artwork sidecars.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = navidrome.group;
      description = "Primary group for the artwork synchronization job.";
    };
    supplementaryGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.optional config.homelab.storage.enable config.homelab.storage.group;
      description = "Additional groups that may write artwork into the library.";
    };
    onBootSec = lib.mkOption {
      type = lib.types.str;
      default = "10min";
      description = "Delay before the first artwork run after boot.";
    };
    onUnitActiveSec = lib.mkOption {
      type = lib.types.str;
      default = "6h";
      description = "Delay between artwork runs.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = navidrome.enable;
        message = "homelab.music.artwork requires services.navidrome.enable.";
      }
      {
        assertion = runtimePath cfg.libraryDir && runtimePath cfg.databaseFile;
        message = "Artwork library and database paths must be canonical absolute runtime paths outside the Nix store.";
      }
    ];
    system.build.musicArtworkSync = syncArtwork;
    systemd.timers.music-artwork = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.onBootSec;
        OnUnitActiveSec = cfg.onUnitActiveSec;
      };
    };
    systemd.services.music-artwork = {
      description = "Maintain canonical covers in the shared music library";
      requires = [
        "navidrome.service"
      ]
      ++ lib.optional config.homelab.storage.enable "homelab-storage.service";
      after = [
        "navidrome.service"
      ]
      ++ lib.optional config.homelab.storage.enable "homelab-storage.service";
      unitConfig.RequiresMountsFor = [ cfg.libraryDir ];
      # The refresh CLI embeds Go and cgo, which need more than 16 OS threads
      # even for serial album updates. Bound parallel Go work separately.
      environment.GOMAXPROCS = "2";
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        SupplementaryGroups = cfg.supplementaryGroups;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        ExecStart = "${lib.getExe syncArtwork} ${
          lib.escapeShellArgs [
            "--database"
            cfg.databaseFile
            "--library"
            cfg.libraryDir
            "--state"
            "/var/lib/${cfg.stateDirectory}"
            "--navidrome"
            (lib.getExe navidrome.finalPackage)
            "--navidrome-config"
            navidromeConfig
          ]
        }";
        UMask = "0002";
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.libraryDir
          (dirOf cfg.databaseFile)
          cacheDir
        ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        MemoryMax = "256M";
        TasksMax = 64;
        TimeoutStartSec = "2h";
      };
    };
  };
}
