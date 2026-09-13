{ homelabModule }: {
  name = "homelab-usenet-credentials";
  nodes.machine = { pkgs, ... }: {
    imports = [
      homelabModule
      ../../examples/usenet.nix
    ];
    system.stateVersion = "26.05";
    homelab.apps.sabnzbd.enable = true;
    homelab.apps.nzbget.enable = true;
    systemd.services.usenet-fixture = {
      wantedBy = [ "multi-user.target" ];
      before = [
        "sabnzbd.service"
        "nzbget.service"
      ];
      requiredBy = [
        "sabnzbd.service"
        "nzbget.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 /run/nix-seal/system/secrets
        umask 077
        printf '%s\n' 'ControlUsername=operator' 'ControlPassword=public-original-password' > /run/nix-seal/system/secrets/nzbget-credentials.conf
        printf '%s\n' '[misc]' 'api_key = public-sab-fixture-api-key' 'nzb_key = public-sab-fixture-nzb-key' 'username = operator' 'password = public-sab-fixture-password' > /run/nix-seal/system/secrets/sabnzbd.ini
      '';
    };
    environment.systemPackages = [ pkgs.python3 ];
  };
  testScript = ''
    import json
    machine.wait_for_unit("nzbget.service")
    machine.wait_for_unit("sabnzbd.service")
    machine.wait_until_succeeds("curl -sf -u operator:public-original-password http://127.0.0.1:6789/jsonrpc/version")
    machine.fail("curl -sf -u nzbget:tegbzn6789 http://127.0.0.1:6789/jsonrpc/version")
    machine.wait_until_succeeds("curl -sf 'http://127.0.0.1:8080/api?mode=version&output=json&apikey=public-sab-fixture-api-key'")
    response = json.loads(machine.succeed("curl -sf 'http://127.0.0.1:8080/api?mode=get_config&section=categories&output=json&apikey=public-sab-fixture-api-key'"))
    assert {item["name"] for item in response["config"]["categories"]} >= {"sonarr", "radarr", "lidarr"}, response
    machine.succeed("printf '%s\\n' 'ControlUsername=operator' 'ControlPassword=public-rotated-password' > /run/nix-seal/system/secrets/nzbget-credentials.conf; systemctl restart nzbget")
    machine.wait_until_succeeds("curl -sf -u operator:public-rotated-password http://127.0.0.1:6789/jsonrpc/version")
    machine.fail("curl -sf -u operator:public-original-password http://127.0.0.1:6789/jsonrpc/version")
    machine.succeed("test $(stat -c %a /var/lib/nzbget/nzbget.conf) = 600")
    machine.succeed("systemctl restart sabnzbd")
    machine.wait_until_succeeds("curl -sf 'http://127.0.0.1:8080/api?mode=version&output=json&apikey=public-sab-fixture-api-key'")
  '';
}
