{ homelabModule, ... }: {
  name = "homelab-miniflux-runtime";

  nodes.machine =
    { pkgs, ... }:
    let
      fixture = pkgs.writers.writePython3 "miniflux_fixture_feed.py" {
        flakeIgnore = [
          "E501"
          "W503"
        ];
      } (builtins.readFile ./scripts/miniflux_fixture_feed.py);
    in
    {
      imports = [ homelabModule ];
      homelab = {
        optional.apps.miniflux.enable = true;
        optional.miniflux.initialFeeds = [
          {
            url = "http://127.0.0.1:18999/feed.xml";
            category = "Fixture reporting";
            crawler = true;
            scraperRules = "article";
          }
        ];
        optional.miniflux.contentUpgrade = {
          revision = "fixture-v1";
          stylesheet = "body { line-height: 1.7; }";
          backfillLimit = 5;
        };
        operations.enable = true;
      };
      services.miniflux.config = {
        FETCHER_ALLOW_PRIVATE_NETWORKS = 1;
        BASE_URL = "http://127.0.0.1:18080";
        MEDIA_PROXY_MODE = "all";
      };
      systemd.services = {
        fixture-feed = {
          wantedBy = [ "multi-user.target" ];
          postStart = (import ../../lib/render-text.nix) ./scripts/wait-miniflux-feed.sh {
            pkgs_coreutils = pkgs.coreutils;
            pkgs_curl = pkgs.curl;
          };
          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python3 ${fixture}";
            DynamicUser = true;
            NoNewPrivileges = true;
          };
        };
        homelab-miniflux-bootstrap = {
          requires = [ "fixture-feed.service" ];
          after = [ "fixture-feed.service" ];
        };
      };
      environment.systemPackages = [ pkgs.curl ];
      virtualisation = {
        cores = 2;
        memorySize = 2048;
      };
    };

  testScript = builtins.readFile ./scripts/miniflux_test.py;
}
