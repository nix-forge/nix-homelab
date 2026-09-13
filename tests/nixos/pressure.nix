{ homelabModule }: {
  name = "homelab-native-pressure";
  nodes.machine = { pkgs, ... }: {
    imports = [
      homelabModule
      ../fixtures/qbittorrent-offline.nix
    ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 1024;
    environment.systemPackages = [ pkgs.python3 ];
    environment.etc = {
      "pressure-fixture/pressure.py".source = ../../scripts/operations/pressure.py;
      "pressure-fixture/run.py".source = ../fixtures/pressure-runtime.py;
    };

    homelab.apps.qbittorrent = {
      enable = true;
      vpn.enable = false;
      credentialsFile = "/run/pressure-qbit.ini";
    };
    systemd.services.pressure-credentials = {
      before = [ "qbittorrent.service" ];
      requiredBy = [ "qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        umask 077
        ${pkgs.python3}/bin/python - <<'PY'
        import base64
        import hashlib
        salt = b'public-pressure-fixture-salt'
        digest = hashlib.pbkdf2_hmac('sha512', b'public-pressure-fixture-password', salt, 100000)
        encoded = base64.b64encode(salt).decode() + ':' + base64.b64encode(digest).decode()
        with open('/run/pressure-qbit.ini', 'w') as handle:
            handle.write('[Preferences]\nWebUI\\Username=admin\nWebUI\\Password_PBKDF2="@ByteArray(' + encoded + ')"\n')
        PY
      '';
    };
  };
  testScript = ''
    from datetime import timedelta

    machine.wait_for_unit("qbittorrent.service")
    machine.wait_for_open_port(8081)
    machine.succeed("PYTHONPATH=/etc/pressure-fixture python /etc/pressure-fixture/run.py", timeout=timedelta(seconds=90))
    machine.succeed("systemctl restart qbittorrent")
    machine.wait_for_open_port(8081)
    machine.succeed("PYTHONPATH=/etc/pressure-fixture python /etc/pressure-fixture/run.py verify", timeout=timedelta(seconds=90))
  '';
}
