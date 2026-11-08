{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.music.shuffle;
  native = config.services.navidrome;
  runtimePath = import ../lib/runtime-path.nix lib;
  program = pkgs.writers.writePython3Bin "configure-music-shuffle" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ../../scripts/media/configure_music_shuffle.py;
  serverUrl =
    (import ../lib/http-url.nix) lib (native.settings.Address or "0.0.0.0") native.settings.Port
    + (lib.removeSuffix "/" (native.settings.BaseURL or ""));
in
{
  options.homelab.music.shuffle = {
    enable = lib.mkEnableOption "private standalone-song smart playlists with editable overrides";
    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = serverUrl;
      description = "Loopback Navidrome API URL. Override for a local TLS or reverse-proxy deployment; trust its CA through the host.";
    };
    usernameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime listener account name file.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime listener password file.";
    };
    readyUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional units that provision the listener account before reconciliation.";
    };
    requiredMounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Actual media mounts that must exist before reconciliation.";
    };
    onBootSec = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "Delay before the first scheduled reconciliation.";
    };
    onUnitActiveSec = lib.mkOption {
      type = lib.types.str;
      default = "1d";
      description = "Delay between reconciliations; existing override playlists remain user-owned.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = native.enable;
        message = "Music shuffle requires services.navidrome.enable.";
      }
      {
        assertion =
          cfg.usernameFile != null
          && cfg.passwordFile != null
          && lib.all runtimePath [
            cfg.usernameFile
            cfg.passwordFile
          ];
        message = "Music shuffle requires both absolute runtime credential files outside the store.";
      }
      {
        assertion =
          builtins.match "https?://(localhost|127[.][0-9]+[.][0-9]+[.][0-9]+|[[]::1[]]):[0-9]+(/[-A-Za-z0-9_./]*)?" cfg.serverUrl
          != null;
        message = "Music shuffle serverUrl must be a credential-free loopback HTTP(S) URL.";
      }
      {
        assertion = !lib.elem "music-shuffle-configuration.service" cfg.readyUnits;
        message = "Music shuffle readiness units must not depend on the shuffle unit itself.";
      }
    ];
    system.build.musicShuffleConfiguration = program;
    systemd.services.music-shuffle-configuration = {
      description = "Maintain private standalone-song shuffle playlists";
      wantedBy = [ "multi-user.target" ];
      requires = [ "navidrome.service" ] ++ cfg.readyUnits;
      after = [ "navidrome.service" ] ++ cfg.readyUnits;
      unitConfig.ConditionPathIsMountPoint = cfg.requiredMounts;
      serviceConfig = {
        Type = "oneshot";
        User = native.user;
        Group = native.group;
        LoadCredential = [
          "username:${lib.replaceStrings [ "%" ] [ "%%" ] cfg.usernameFile}"
          "password:${lib.replaceStrings [ "%" ] [ "%%" ] cfg.passwordFile}"
        ];
        ExecStart =
          (import ../../lib/systemd-args.nix) [
            (lib.getExe program)
            "--server-url"
            cfg.serverUrl
          ]
          + " --username-file %d/username --password-file %d/password";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
        TimeoutStartSec = "5m";
        MemoryMax = "128M";
      };
    };
    systemd.timers.music-shuffle-configuration = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.onBootSec;
        OnUnitActiveSec = cfg.onUnitActiveSec;
      };
    };
  };
}
