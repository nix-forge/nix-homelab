{ homelabModule }: {
  name = "homelab-media-runtime";
  nodes.machine = { pkgs, ... }: {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 4096;
    virtualisation.diskSize = 8192;
    homelab = {
      profiles.media.enable = true;
      apps = {
        qbittorrent = {
          vpn.enable = false;
          credentialsFile = "/run/test-qbit-webui.ini";
        };
        sabnzbd.enable = true;
        nzbget.enable = true;
        lidarr.enable = true;
        navidrome.enable = true;
        audiobookshelf.enable = true;
      };
    };
    systemd.services.test-qbit-credentials = {
      before = [ "qbittorrent.service" ];
      requiredBy = [ "qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        umask 077
        ${pkgs.python3}/bin/python - <<'PYKEY'
        import base64
        import hashlib
        salt = b"public-disposable-test-salt"
        digest = hashlib.pbkdf2_hmac("sha512", b"fixture-password", salt, 100000)
        encoded = base64.b64encode(salt).decode() + ":" + base64.b64encode(digest).decode()
        with open("/run/test-qbit-webui.ini", "w") as f:
            f.write("[Preferences]\nWebUI\\Username=fixture\nWebUI\\Password_PBKDF2=\"@ByteArray(" + encoded + ")\"\n")
        PYKEY
      '';
    };
    environment.systemPackages = [ pkgs.curl ];
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    for service, port in [
        ("sonarr", 8989), ("radarr", 7878), ("lidarr", 8686), ("bazarr", 6767),
        ("prowlarr", 9696), ("seerr", 5055), ("jellyfin", 8096),
        ("qbittorrent", 8081), ("sabnzbd", 8080), ("nzbget", 6789),
        ("navidrome", 4533), ("audiobookshelf", 8000),
    ]:
        machine.wait_for_unit(f"{service}.service")
        machine.wait_until_succeeds(f"curl -s -o /dev/null -w '%{{http_code}}' --max-time 3 http://127.0.0.1:{port}/ | grep -E '^(200|301|302|303|307|308|401)$'")
    # Current qBittorrent returns an empty 204 after login. Prove the cookie can
    # access a protected API rather than matching the older literal Ok. body.
    login = "curl -fsS --max-time 3 -c /tmp/qbit-cookie --data username=fixture --data password=fixture-password http://127.0.0.1:8081/api/v2/auth/login"
    protected_api = "curl -fsS --max-time 3 http://127.0.0.1:8081/api/v2/app/version"
    machine.fail(protected_api)
    machine.wait_until_succeeds(login, timeout=30)
    assert machine.succeed(protected_api + " -b /tmp/qbit-cookie").strip()
    # Exercise shared-group hardlinks across distinct service identities.
    machine.succeed("runuser -u qbittorrent -g qbittorrent -G media -- sh -c 'umask 0007; printf test > /srv/media/downloads/torrents/test-media'")
    machine.succeed("runuser -u sonarr -g sonarr -G media -- ln /srv/media/downloads/torrents/test-media /srv/media/library/tv/test-media")
    machine.succeed("test $(stat -c %i /srv/media/downloads/torrents/test-media) = $(stat -c %i /srv/media/library/tv/test-media)")
    machine.fail("runuser -u nobody -- cat /srv/media/library/tv/test-media")
    # Reader-created private files need no shared-media write permissions.
    assert machine.succeed("systemctl show jellyfin -p UMask --value").strip() == "0077"
    # Credentials remain inaccessible to a different member of the media group.
    machine.succeed("test -s /var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf")
    machine.fail("runuser -u sonarr -g sonarr -G media -- cat /var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf")
    # The running player sees a read-only library in its own mount namespace.
    machine.fail("nsenter -t $(systemctl show -p MainPID --value jellyfin) -m -- touch /srv/media/library/player-write")
    machine.succeed("systemctl restart sonarr radarr prowlarr seerr qbittorrent")
    for service in ["sonarr", "radarr", "prowlarr", "seerr", "qbittorrent"]:
        machine.wait_for_unit(f"{service}.service")
    machine.wait_until_succeeds(login, timeout=30)
    assert machine.succeed(protected_api + " -b /tmp/qbit-cookie").strip()
    machine.succeed("sed -i 's/Username=fixture/Username=rotated/' /run/test-qbit-webui.ini")
    machine.succeed("systemctl restart qbittorrent")
    machine.wait_for_unit("qbittorrent.service")
    machine.wait_until_succeeds(login.replace("username=fixture", "username=rotated"), timeout=30)
    assert machine.succeed(protected_api + " -b /tmp/qbit-cookie").strip()
    machine.fail(login)
  '';
}
