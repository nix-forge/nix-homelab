{ homelabModule }: {
  name = "homelab-pinchflat-migration";
  nodes.machine =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      legacySource = pkgs.fetchFromGitHub {
        owner = "kieraneglin";
        repo = "pinchflat";
        rev = "4f8cba3f9c0edc567687c6a007aaa80b311c6899";
        hash = "sha256-45lw/48WTlfwTMWsCryNY3g3W9Ff31vMvw0W9znAJGk=";
      };
    in
    {
      imports = [ homelabModule ];
      system.stateVersion = "26.05";
      virtualisation.memorySize = 2048;
      environment.systemPackages = [
        pkgs.curl
        pkgs.sqlite
      ];
      homelab = {
        optional.apps.pinchflat.enable = true;
        storage = {
          rootDir = "/mnt/media/data";
          requiredMounts = [ "/mnt/media" ];
        };
      };
      services.pinchflat.secretsFile = "/run/pinchflat.env";
      systemd.services = {
        pinchflat-fixture-secrets = {
          before = [
            "pinchflat-legacy-fixture.service"
            "pinchflat.service"
          ];
          requiredBy = [
            "pinchflat-legacy-fixture.service"
            "pinchflat.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            umask 077
            fixture_secret=$(${pkgs.openssl}/bin/openssl rand -hex 64)
            fixture_password=$(${pkgs.openssl}/bin/openssl rand -hex 32)
            printf 'SECRET_KEY_BASE=%s\nBASIC_AUTH_USERNAME=fixture\nBASIC_AUTH_PASSWORD=%s\n' "$fixture_secret" "$fixture_password" > /run/pinchflat.env
            printf 'machine 127.0.0.1 login fixture password %s\n' "$fixture_password" > /run/pinchflat.netrc
          '';
        };
        pinchflat-legacy-fixture = {
          requires = [
            "homelab-optional-storage.service"
            "pinchflat-fixture-secrets.service"
          ];
          after = [
            "homelab-optional-storage.service"
            "pinchflat-fixture-secrets.service"
          ];
          before = [ "pinchflat.service" ];
          requiredBy = [ "pinchflat.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = config.services.pinchflat.user;
            Group = config.services.pinchflat.group;
            SupplementaryGroups = [ config.homelab.storage.group ];
            StateDirectory = "pinchflat";
            UMask = "0007";
            Environment = config.systemd.services.pinchflat.serviceConfig.Environment ++ [
              "LEGACY_MIGRATIONS=${legacySource}/priv/repo/migrations"
            ];
            EnvironmentFile = config.services.pinchflat.secretsFile;
          };
          script = ''
            exec ${lib.getExe config.services.pinchflat.package} eval 'Code.eval_file("${../fixtures/pinchflat-legacy-state.exs}")'
          '';
        };
      };
    };
  testScript = builtins.readFile ./pinchflat.py;
}
