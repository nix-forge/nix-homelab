{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.music.lyrics;
  native = config.services.navidrome;
  runtimePath = import ../lib/runtime-path.nix lib;
  program = pkgs.writers.writePython3Bin "sync-music-lyrics" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../../scripts/media/lyrics.py);
in
{
  options.homelab.music.lyrics = {
    enable = lib.mkEnableOption "conservative shared LRC lyric enrichment from LRCLIB";
    libraryDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.homelab.storage.libraryDir}/music";
      description = "Shared writable music library; existing lyrics and audio are preserved.";
    };
    databaseFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.services.navidrome.settings.DataFolder or "/var/lib/navidrome"}/navidrome.db";
      description = "Read-only Navidrome index supplying track identity.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = native.user;
      description = "Account with read access to the Navidrome index and write access to lyric sidecars.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = if config.homelab.storage.enable then config.homelab.storage.group else native.group;
      description = "Sidecar-writing group; prepared shared storage supplies its media group when enabled.";
    };
    maxRequests = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Maximum serial exact-match requests per run.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = native.enable;
        message = "Shared lyrics require services.navidrome.enable and writable library access.";
      }
      {
        assertion = runtimePath cfg.libraryDir && runtimePath cfg.databaseFile;
        message = "Lyrics require canonical absolute runtime library and database paths.";
      }
    ];
    system.build.musicLyricsSync = program;
    systemd.timers.music-lyrics = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
    systemd.services.music-lyrics = {
      description = "Fill missing shared synchronized lyrics";
      requires = [
        "navidrome.service"
      ]
      ++ lib.optional config.homelab.storage.enable "homelab-storage.service";
      after = [
        "navidrome.service"
      ]
      ++ lib.optional config.homelab.storage.enable "homelab-storage.service";
      unitConfig.RequiresMountsFor = [ cfg.libraryDir ];
      serviceConfig = {
        Type = "oneshot";
        # Reuse index access, but keep the player itself read-only.
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "music-lyrics";
        StateDirectoryMode = "0700";
        ExecStart = "${lib.getExe program} ${
          lib.escapeShellArgs [
            "--database"
            cfg.databaseFile
            "--library"
            cfg.libraryDir
            "--state"
            "/var/lib/music-lyrics/retry.sqlite"
            "--limit"
            (toString cfg.maxRequests)
          ]
        }";
        UMask = "0027";
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.libraryDir ];
        ReadOnlyPaths = [ (dirOf cfg.databaseFile) ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        MemoryMax = "128M";
        TasksMax = 8;
        CPUQuota = "25%";
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "1h";
      };
    };
  };
}
