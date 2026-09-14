{
  config,
  lib,
  pkgs,
  ...
}:
let
  catalog = import ../catalog.nix;
  cfg = config.homelab.optional;
  storage = config.homelab.storage;
  names = builtins.attrNames catalog.optional;
  enabled = name: cfg.apps.${name}.enable;
  selected = lib.filter enabled names;
  nativeSelected = lib.filter (name: catalog.optional.${name}.nativeService or true) selected;
  withMediaAccess =
    access: lib.filter (name: (catalog.optional.${name}.mediaAccess or null) == access) selected;
  readers = withMediaAccess "reader";
  writers = withMediaAccess "writer";
  media = readers ++ writers;
  units = lib.concatMap (
    name:
    if name == "immich" then
      [ "immich-server" ]
      ++ lib.optional config.services.immich.machine-learning.enable "immich-machine-learning"
    else if name == "paperless" then
      [
        "paperless-web"
        "paperless-consumer"
        "paperless-task-queue"
        "paperless-scheduler"
      ]
    else if name == "karakeep" then
      [
        "homelab-karakeep-secrets"
        "karakeep-init"
        "karakeep-web"
        "karakeep-workers"
        "karakeep-browser"
        "meilisearch"
      ]
    else if name == "scrutiny" then
      [ "scrutiny" ]
    else
      [ name ]
  ) selected;
  guardedDirs =
    lib.optionals (enabled "cross-seed") config.services.cross-seed.settings.linkDirs
    ++ lib.optionals (enabled "shelfmark") [ config.services.shelfmark.environment.INGEST_DIR ]
    ++ lib.optionals (enabled "pinchflat") [ config.services.pinchflat.mediaDir ];
in
{
  options.homelab.optional.apps = lib.genAttrs names (name: {
    enable = lib.mkEnableOption "${name} with private homelab defaults";
  });
  config = lib.mkMerge [
    (lib.mkIf (selected != [ ]) {
      networking.firewall.enable = lib.mkDefault true;
      services = lib.genAttrs nativeSelected (_: {
        enable = true;
      });
      # Preserve upstream sandbox exceptions, including browser and JIT runtimes.
      systemd.services = lib.genAttrs units (name: {
        serviceConfig = {
          CPUWeight = lib.mkDefault 25;
          IOWeight = lib.mkDefault 25;
          Nice = lib.mkDefault 10;
          NoNewPrivileges = lib.mkDefault true;
          ProtectHome = lib.mkDefault (name != "syncthing");
          PrivateTmp = lib.mkDefault true;
          ProtectSystem = lib.mkDefault (if name == "syncthing" then "full" else "strict");
          RestrictSUIDSGID = lib.mkDefault true;
        };
      });
    })
    (lib.mkIf (media != [ ]) {
      homelab.storage.enable = true;
      assertions = map (path: {
        assertion =
          lib.hasPrefix "${storage.rootDir}/" path
          && !(lib.hasInfix "/../" "${path}/")
          && !(lib.hasInfix "\n" path);
        message = "Optional media output directories must be descendants of homelab.storage.rootDir without parent traversal.";
      }) guardedDirs;
      systemd.services = {
        homelab-optional-storage = {
          description = "Prepare optional media outputs after the required mount checks";
          requires = [ "homelab-storage.service" ];
          after = [ "homelab-storage.service" ];
          before = map (name: "${name}.service") media;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0007";
          };
          script = ''
            ${pkgs.python3}/bin/python3 ${../../scripts/storage/prepare.py} ${lib.escapeShellArg storage.group} ${lib.escapeShellArgs guardedDirs}
          '';
        };
      }
      // lib.genAttrs media (name: {
        after = [ "homelab-optional-storage.service" ];
        requires = [ "homelab-optional-storage.service" ];
        unitConfig.RequiresMountsFor = storage.requiredMounts ++ [ storage.rootDir ];
        serviceConfig = {
          SupplementaryGroups = [ storage.group ];
          UMask = lib.mkForce "0007";
        }
        // lib.optionalAttrs (builtins.elem name readers) { BindReadOnlyPaths = [ storage.libraryDir ]; }
        // lib.optionalAttrs (name == "cross-seed") {
          # One bind mount preserves hardlinks across data and link directories.
          ReadWritePaths = [
            storage.rootDir
            config.services.cross-seed.configDir
          ];
        }
        // lib.optionalAttrs (name == "unpackerr") {
          ReadWritePaths = [ storage.downloadsDir ];
          BindReadOnlyPaths = [ storage.libraryDir ];
        }
        // lib.optionalAttrs (name == "shelfmark") {
          ReadWritePaths = [ config.services.shelfmark.environment.INGEST_DIR ];
          BindReadOnlyPaths = [ storage.downloadsDir ];
        }
        // lib.optionalAttrs (name == "pinchflat") {
          ReadWritePaths = [ config.services.pinchflat.mediaDir ];
        };
      });
    })
  ];
}
