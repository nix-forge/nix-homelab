{ homelabModule }: {
  name = "homelab-storage-missing";
  nodes.machine = { pkgs, ... }: {
    imports = [
      homelabModule
      ../fixtures/nzbget-credentials.nix
    ];
    system.stateVersion = "26.05";
    users.groups.fixture-downloads = { };
    users.users.fixture-downloads = {
      isSystemUser = true;
      group = "fixture-downloads";
    };
    services.slskd = {
      user = "fixture-downloads";
      group = "fixture-downloads";
      package = pkgs.writeShellScriptBin "slskd" "exec ${pkgs.coreutils}/bin/sleep infinity";
    };
    systemd.services.slskd-fixture-credentials = {
      requiredBy = [ "slskd.service" ];
      before = [ "slskd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = ''
        for name in SLSKD_SLSK_USERNAME SLSKD_SLSK_PASSWORD SLSKD_USERNAME SLSKD_PASSWORD SLSKD_API_KEY SLSKD_JWT_KEY; do
          printf '%s=public-fixture-credentials-only-1234567890\n' "$name"
        done > /run/slskd-fixture.env
      '';
    };
    homelab = {
      apps.nzbget.enable = true;
      apps.navidrome.enable = true;
      apps.slskd = {
        enable = true;
        credentialsFile = "/run/slskd-fixture.env";
        vpn = {
          enable = false;
          allowUnconfined = true;
        };
        downloadsDir = "/mnt/absent/media/downloads/soulseek/complete";
        incompleteDir = "/mnt/absent/media/downloads/soulseek/incomplete";
        downloadGroup = "media";
        downloadDirectoryMode = "2770";
      };
      storage = {
        rootDir = "/mnt/absent/media";
        requiredMounts = [ "/mnt/absent" ];
      };
    };
  };
  testScript = builtins.readFile ./scripts/storage_missing_test.py;
}
