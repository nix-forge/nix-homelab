{ homelabModule }: {
  name = "homelab-maintainerr-runtime";
  nodes.machine = { pkgs, ... }: {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 3072;
    virtualisation.diskSize = 8192;
    environment.systemPackages = [ pkgs.curl ];
    fileSystems."/srv/media" = {
      device = "tmpfs";
      fsType = "tmpfs";
    };
    homelab.optional = {
      apps.maintainerr.enable = true;
      maintainerr = {
        htpasswdFile = "/etc/maintainerr-test.htpasswd";
        policyFile = "/etc/maintainerr-test-policy.json";
      };
      jellyfinIgnore = {
        enable = true;
        user = "homelab-maintainerr";
        mountPoint = "/srv/media";
        roots = [ "/srv/media/shows" ];
      };
    };
    environment.etc."maintainerr-test.htpasswd".text = "viewer:{SHA}qUqP5cyxm6YcTAhz05Hph5gvu9M=\n";
    environment.etc."maintainerr-test-policy.json".text = ''{"rules":[]}'';
  };
  testScript = builtins.readFile ./scripts/maintainerr_test.py;
}
