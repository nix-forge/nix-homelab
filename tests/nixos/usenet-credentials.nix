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
      script = builtins.readFile ./scripts/prepare-usenet-credentials.sh;
    };
    environment.systemPackages = [ pkgs.python3 ];
  };
  testScript = builtins.readFile ./scripts/usenet_credentials_test.py;
}
