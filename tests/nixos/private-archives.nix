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
    systemd.services.restic-backups-fixture.preStart = lib.mkBefore ''
      printf '%s' disposable-backup-password > /run/restic-password
      chmod 600 /run/restic-password
    '';
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
  testScript = ''
    import json
    import shlex
    from datetime import timedelta

    def restore_state(node, database=None):
        node.succeed("systemctl start restic-backups-fixture")
        node.succeed("restic-fixture restore latest --target /var/lib/restored")
        inventory = json.loads(node.succeed("cat /etc/homelab/state-inventory.json"))
        units = sorted({unit for entry in inventory.values() for unit in entry["units"]})
        node.succeed("systemctl stop " + " ".join(map(shlex.quote, units)))
        # Remove the live app state to establish that API success depends on restore.
        # Restore top-level sources before nested native media/consume directories.
        copies = []
        for name, entry in inventory.items():
            for index, original in enumerate(entry["paths"]):
                copies.append((original, f"/var/lib/restored/var/lib/homelab-recovery/snapshot/services/{name}/{index}"))
        for original, saved in sorted(copies, key=lambda item: len(item[0])):
            resolved = node.succeed("realpath " + shlex.quote(original)).strip()
            node.succeed("rm -rf -- " + shlex.quote(resolved))
            node.succeed("cp -a -- " + shlex.quote(saved) + " " + shlex.quote(resolved))
        if database:
            # pg_restore replaces existing data and restores original roles and ACLs.
            node.succeed(f"homelab-restore-postgresql {database} /var/lib/restored/var/lib/homelab-recovery/snapshot/databases/{database}.dump --replace")
        node.succeed("systemctl start " + " ".join(map(shlex.quote, units)))

    def documents(node, database=None):
        node.start()
        node.wait_for_unit("paperless-web.service")
        node.wait_for_unit("paperless-task-queue.service")
        node.wait_until_succeeds("curl -fsS -u admin:disposable-password http://127.0.0.1:28981/api/documents/")
        node.succeed("printf '%s' 'Public generated archive recovery fixture.' > /tmp/document.txt")
        node.succeed("curl -fsS -u admin:disposable-password -F document=@/tmp/document.txt http://127.0.0.1:28981/api/documents/post_document/")
        node.wait_until_succeeds("test $(curl -fsS -u admin:disposable-password http://127.0.0.1:28981/api/documents/ | jq .count) = 1", timeout=timedelta(minutes=3))
        document = json.loads(node.succeed("curl -fsS -u admin:disposable-password http://127.0.0.1:28981/api/documents/"))["results"][0]
        original = f"curl -fsS -u admin:disposable-password 'http://127.0.0.1:28981/api/documents/{document['id']}/download/?original=true'"
        node.succeed(original + " | cmp /tmp/document.txt -")
        restore_state(node, database)
        node.wait_until_succeeds(original + " | cmp /tmp/document.txt -")
        node.succeed("curl -fsS -u admin:disposable-password http://127.0.0.1:28981/api/documents/ | jq -e '.count == 1'")
        node.shutdown()

    documents(sqlite)
    documents(postgres, "paperless")
    photos.start()
    photos.wait_for_unit("immich-server.service")
    photos.wait_until_succeeds("curl -fsS http://127.0.0.1:2283/api/server/ping", timeout=timedelta(minutes=3))
    photos.succeed("curl -fsS --json '{\"email\":\"fixture@example.invalid\",\"name\":\"Fixture\",\"password\":\"disposable-password\"}' http://127.0.0.1:2283/api/auth/admin-sign-up")
    login = "curl -fsS --json '{\"email\":\"fixture@example.invalid\",\"password\":\"disposable-password\"}' http://127.0.0.1:2283/api/auth/login"
    token = json.loads(photos.succeed(login))["accessToken"]
    key = json.loads(photos.succeed(f"curl -fsS -H 'Cookie: immich_access_token={token}' --json '{{\"name\":\"fixture\",\"permissions\":[\"all\"]}}' http://127.0.0.1:2283/api/api-keys"))["secret"]
    photos.succeed(f"immich login http://127.0.0.1:2283/api {key}")
    photos.succeed("magick -size 40x40 gradient:red-blue /tmp/photo.jpg")
    upload = json.loads(photos.succeed("immich upload --json-output /tmp/photo.jpg | tail -n +4"))
    asset = upload["newAssets"][0]["id"]
    photos.wait_until_succeeds(f"curl -fsS -H 'Cookie: immich_access_token={token}' http://127.0.0.1:2283/api/assets/{asset}/thumbnail -o /tmp/thumbnail", timeout=timedelta(minutes=3))
    original = f"curl -fsS -H 'x-api-key: {key}' http://127.0.0.1:2283/api/assets/{asset}/original"
    photos.succeed(original + " | cmp /tmp/photo.jpg -")
    restore_state(photos, "immich")
    photos.wait_until_succeeds(login)
    photos.succeed(original + " | cmp /tmp/photo.jpg -")
    photos.succeed(f"curl -fsS -H 'x-api-key: {key}' http://127.0.0.1:2283/api/assets/{asset} | jq -e '.id == \"{asset}\"'")
  '';
}
