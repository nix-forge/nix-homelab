{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.jellyfinCaptions;
  runtimePath = import ../../lib/runtime-path.nix lib;
  json = pkgs.formats.json { };
  users = lib.imap0 (index: file: {
    name = "user-${toString index}";
    inherit file;
  }) cfg.usernameFiles;
  specification = json.generate "jellyfin-caption-profiles.json" {
    inherit (cfg)
      serverUrl
      profiles
      revision
      previousRevision
      previousProfiles
      ;
    usernameCredentials = map (user: user.name) users;
  };
  program = pkgs.writers.writePython3Bin "configure-captions" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ../../../scripts/media/configure_captions.py;
  profileSettings = lib.types.attrsOf (lib.types.attrsOf json.type);
in
{
  options.homelab.optional.jellyfinCaptions = {
    enable = lib.mkEnableOption "versioned per-user Moonfin caption defaults that preserve subsequent UI edits";
    pluginName = lib.mkOption {
      type = lib.types.str;
      default = config.homelab.optional.jellyfinPlugins.moonbase.pluginName;
      description = "Declared Moonbase plugin package key providing settings synchronization.";
    };
    serverUrl = lib.mkOption {
      type = lib.types.str;
      default =
        if config.homelab.integrations.jellyfin != null then
          config.homelab.integrations.jellyfin.url
        else
          "http://127.0.0.1:8096";
      description = "Loopback Jellyfin API base URL, including a native path prefix when configured.";
    };
    adminUsernameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime administrator login name file.";
    };
    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime administrator password file.";
    };
    usernameFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Runtime login name files for the accounts receiving the preset. The administrator is included only if listed.";
    };
    profiles = lib.mkOption {
      type = profileSettings;
      default = { };
      description = "Moonfin client profiles and caption fields to seed once per revision. Personal preferences belong in the consumer.";
    };
    revision = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_-]+";
      default = "v1";
      description = "Operator-selected preset revision. Completed revisions preserve later UI edits.";
    };
    previousRevision = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9_-]+");
      default = null;
      description = "Optional immediately preceding managed revision to migrate conservatively.";
    };
    previousProfiles = lib.mkOption {
      type = profileSettings;
      default = { };
      description = "Prior preset values. Migration updates only unchanged fields and missing fields.";
    };
    readyUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional account-provisioning units that must finish first.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_-]+";
      default = "homelab-captions";
      description = "Private completion-marker state directory.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.jellyfin.enable;
        message = "Caption seeding requires services.jellyfin.enable.";
      }
      {
        assertion = builtins.hasAttr cfg.pluginName config.homelab.optional.jellyfinPlugins.packages;
        message = "Caption seeding requires a declared Moonbase plugin package.";
      }
      {
        assertion =
          cfg.adminUsernameFile != null
          && cfg.adminPasswordFile != null
          && cfg.usernameFiles != [ ]
          && lib.all runtimePath (
            [
              cfg.adminUsernameFile
              cfg.adminPasswordFile
            ]
            ++ cfg.usernameFiles
          );
        message = "Caption seeding requires runtime administrator credentials and selected username files outside the store.";
      }
      {
        assertion =
          cfg.profiles != { }
          && lib.all (
            name:
            lib.elem name [
              "global"
              "desktop"
              "mobile"
              "tv"
            ]
          ) (lib.attrNames cfg.profiles)
          && lib.all (
            profile:
            profile != { }
            && lib.all (field: field == "assDirectPlay" || lib.hasPrefix "subtitle" field) (
              lib.attrNames profile
            )
          ) (lib.attrValues cfg.profiles);
        message = "Caption seeding requires nonempty caption-only profile settings.";
      }
      {
        assertion =
          cfg.previousRevision == null
          || (cfg.previousRevision != cfg.revision && cfg.previousProfiles != { });
        message = "Caption migration requires a distinct previous revision and its prior profile values.";
      }
      {
        assertion =
          builtins.match "https?://(localhost|127[.][0-9]+[.][0-9]+[.][0-9]+|[[]::1[]]):[0-9]+(/[-A-Za-z0-9_./]*)?" cfg.serverUrl
          != null;
        message = "Caption seeding serverUrl must be a credential-free loopback HTTP(S) URL.";
      }
      {
        assertion = !lib.elem "homelab-caption-setup.service" cfg.readyUnits;
        message = "Caption readiness units must not depend on the caption unit itself.";
      }
    ];
    system.build.jellyfinCaptionSetup = program;
    systemd.services.homelab-caption-setup = {
      description = "Seed adjustable Moonfin captions for selected accounts";
      wantedBy = [ "multi-user.target" ];
      requires = [ "jellyfin.service" ] ++ cfg.readyUnits;
      after = [ "jellyfin.service" ] ++ cfg.readyUnits;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = (import ../../../lib/systemd-args.nix) [
          (lib.getExe program)
          specification
        ];
        LoadCredential = [
          "admin-username:${lib.replaceStrings [ "%" ] [ "%%" ] cfg.adminUsernameFile}"
          "admin-password:${lib.replaceStrings [ "%" ] [ "%%" ] cfg.adminPasswordFile}"
        ]
        ++ map (user: "${user.name}:${lib.replaceStrings [ "%" ] [ "%%" ] user.file}") users;
        DynamicUser = true;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        UMask = "0077";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
        TimeoutStartSec = "3min";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  };
}
