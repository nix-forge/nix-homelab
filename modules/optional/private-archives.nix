{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = name: config.homelab.optional.apps.${name}.enable;
in
{
  config = lib.mkMerge [
    (lib.mkIf (enabled "immich") {
      services.immich = {
        host = lib.mkDefault "127.0.0.1";
        openFirewall = lib.mkDefault false;
        settings.job =
          lib.genAttrs
            [
              "backgroundTask"
              "smartSearch"
              "metadataExtraction"
              "faceDetection"
              "search"
              "sidecar"
              "library"
              "migration"
              "thumbnailGeneration"
              "videoConversion"
              "notifications"
              "ocr"
              "workflow"
              "editor"
              "integrityCheck"
            ]
            (_: {
              concurrency = lib.mkDefault 1;
            });
      };
    })
    (lib.mkIf (enabled "paperless") {
      assertions = [
        {
          assertion = config.services.paperless.environmentFile != null;
          message = "Paperless requires a user-provided runtime environmentFile containing PAPERLESS_SECRET_KEY.";
        }
      ];
      services.paperless = {
        # Upstream tests use libc local time alongside Python ZoneInfo. Supply
        # libc's timezone database in the sandbox so their dates agree.
        package = lib.mkDefault (
          pkgs.paperless-ngx.overrideAttrs { TZDIR = "${pkgs.tzdata}/share/zoneinfo"; }
        );
        address = lib.mkDefault "127.0.0.1";
        settings = {
          PAPERLESS_TASK_WORKERS = lib.mkDefault 1;
          PAPERLESS_THREADS_PER_WORKER = lib.mkDefault 1;
          PAPERLESS_OCR_LANGUAGE = lib.mkDefault "eng";
          PAPERLESS_OCR_MODE = lib.mkDefault "auto";
          PAPERLESS_CONSUMER_RECURSIVE = lib.mkDefault false;
          PAPERLESS_AI_ENABLED = lib.mkDefault false;
        };
      };
    })
    (lib.mkIf (enabled "syncthing") {
      # Syncthing creates declared folders at runtime. A blanket read-only root
      # would prevent both its config bootstrap and new folder creation.
      systemd.services.syncthing.unitConfig.RequiresMountsFor = [
        config.services.syncthing.configDir
        config.services.syncthing.databaseDir
      ]
      ++ map (folder: folder.path) (
        lib.attrValues (
          lib.filterAttrs (_: folder: folder.enable) config.services.syncthing.settings.folders
        )
      );
      services.syncthing = {
        openDefaultPorts = lib.mkDefault false;
        guiAddress = lib.mkDefault "127.0.0.1:8384";
        settings.options = {
          globalAnnounceEnabled = lib.mkDefault false;
          localAnnounceEnabled = lib.mkDefault false;
          relaysEnabled = lib.mkDefault false;
          urAccepted = lib.mkDefault (-1);
        };
      };
    })
  ];
}
