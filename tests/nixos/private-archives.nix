{ homelabModule }:
let
  base = { pkgs, lib, ... }: {
    imports = [
      homelabModule
      ../../modules/operations
    ];
    system.stateVersion = "26.05";
    virtualisation = {
      memorySize = 4096;
      cores = 2;
      diskSize = 8192;
    };
    environment.systemPackages = [
      pkgs.imagemagick
      pkgs.immich-cli
      pkgs.jq
      pkgs.python3
    ];
    homelab.operations = {
      enable = true;
      backup.job = "fixture";
    };
    systemd.services.restic-backups-fixture.preStart = lib.mkBefore (
      builtins.readFile ./scripts/prepare-private-archive-password.sh
    );
    services.restic.backups.fixture = {
      repository = "/var/lib/restic-fixture";
      passwordFile = "/run/restic-password";
      initialize = true;
      timerConfig = null;
      checkOpts = [ "--read-data" ];
    };
  };
  documents = postgres: { ... }: {
    imports = [ base ];
    homelab.optional.apps.paperless.enable = true;
    homelab.operations = {
      paperlessDatabase = if postgres then "postgresql" else "sqlite";
      postgresql = if postgres then { paperless.database = "paperless"; } else { };
    };
    services.paperless = {
      passwordFile = "/etc/paperless-fixture-password";
      environmentFile = "/etc/paperless-fixture-environment";
      database.createLocally = postgres;
      settings.PAPERLESS_TIME_ZONE = "UTC";
    };
    environment.etc = {
      "paperless-fixture-password".text = "disposable-password";
      "paperless-fixture-environment".text =
        "PAPERLESS_SECRET_KEY=public-fixture-secret-not-for-deployment\n";
    };
  };
in
{
  name = "homelab-private-archive-recovery";
  nodes = {
    sqlite = documents false;
    postgres = documents true;
    photos = { ... }: {
      imports = [ base ];
      homelab.optional.apps.immich.enable = true;
      homelab.operations.postgresql.immich.database = "immich";
      services.immich = {
        machine-learning.enable = false;
        settings = {
          machineLearning.enabled = false;
          backup.database.enabled = false;
        };
      };
    };
  };
  testScript = builtins.readFile ./scripts/private_archives_test.py;
}
