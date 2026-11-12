{ homelabModule, ... }: {
  name = "homelab-vpn-namespace";

  nodes.machine =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      namespace = config.services.vpnConfinement.namespaces.vpnapps;
      hostAddress = namespace.derived.hostLink.hostAddressIPv4;
      namespaceAddress = config.homelab.vpn.namespace.bindAddress;
    in
    {
      environment.etc."vpn_probe.py".source = ./scripts/vpn_probe.py;

      imports = [
        homelabModule
        ../fixtures/qbittorrent-offline.nix
      ];
      system.stateVersion = "26.05";
      virtualisation.memorySize = 3072;

      networking = {
        useDHCP = false;
        interfaces.eth1.ipv4.addresses = lib.mkForce [
          {
            address = "192.168.1.1";
            prefixLength = 24;
          }
        ];
        firewall = {
          # Deliberately permit LAN forwarding to exercise the namespace's own
          # ingress policy, rather than depending on the host's forward policy.
          filterForward = false;
          interfaces = {
            eth1.allowedTCPPorts = [ 18081 ];
            wg-test-peer = {
              allowedTCPPorts = [
                53
                443
                18080
              ];
              allowedUDPPorts = [
                53
                19000
              ];
            };
            ${namespace.hostLink.hostIf}.allowedTCPPorts = [ 18081 ];
          };
        };
      };
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
      services.resolved.enable = true;

      homelab.storage.enable = true;
      homelab.indexerProxy = {
        enable = true;
        passwordFile = "/run/indexer-proxy-password";
      };
      systemd.tmpfiles.rules = [
        "f /run/indexer-proxy-password 0600 microsocks microsocks - fixture-password"
      ];
      homelab.vpn = {
        enable = true;
        interface = {
          privateKeyFile = "/run/wg-test/client.key";
          addressIPv4 = "10.71.216.231";
          dns = [ "10.71.216.232" ];
        };
        peer = {
          # Public fixture keys, exclusively for this isolated VM test.
          publicKey = "iCXIkYspxjCzUbbO4CThCIQGu5mVoG7mWw8Ac0wprlg=";
          endpointHost = "127.0.0.1";
          endpointPort = 51821;
          persistentKeepalive = 1;
        };
      };
      homelab.apps.qbittorrent = {
        enable = true;
        vpn.enable = true;
      };

      homelab.apps.sabnzbd = {
        enable = true;
        vpn.enable = true;
      };
      homelab.apps.nzbget = {
        enable = true;
        vpn.enable = true;
        credentialsFile = "/etc/nzbget-fixture.conf";
      };
      environment.etc."nzbget-fixture.conf".text = ''
        ControlUsername=operator
        ControlPassword=public-vpn-fixture-password
      '';
      homelab.apps.prowlarr = {
        enable = true;
        vpn.enable = true;
      };
      homelab.apps.slskd = {
        enable = true;
        credentialsFile = "/etc/slskd-fixture.env";
      };
      environment.etc."slskd-fixture.env".text = ''
        SLSKD_SLSK_USERNAME=fixture
        SLSKD_SLSK_PASSWORD=fixture-password-long
        SLSKD_USERNAME=operator
        SLSKD_PASSWORD=fixture-web-password-long
        SLSKD_API_KEY=fixture-api-key-long
        SLSKD_JWT_KEY=fixture-jwt-signing-key-longer-than-thirty-two-characters
      '';

      # This peer stays in the host namespace. It is a real encrypted tunnel with
      # no provider account, public Internet access or deployment secrets.
      systemd.services.test-wireguard-peer = {
        requiredBy = [ "wireguard-wg0.service" ];
        before = [ "wireguard-wg0.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.coreutils
          pkgs.iproute2
          pkgs.wireguard-tools
        ];
        script = builtins.readFile ./scripts/configure-vpn-peer.sh;
        postStop = (import ../../lib/render-text.nix) ./scripts/remove-vpn-peer.sh {
          pkgs_iproute2 = pkgs.iproute2;
        };
      };
      services.dnsmasq = {
        enable = true;
        settings = {
          bind-interfaces = true;
          listen-address = [
            "10.71.216.232"
            "10.71.216.233"
          ];
          no-resolv = true;
          address = "/vpn-fixture.test/10.71.216.232";
        };
      };
      systemd.services.dnsmasq = {
        requires = [ "test-wireguard-peer.service" ];
        after = [ "test-wireguard-peer.service" ];
      };
      systemd.services.test-tunnel-http = {
        wantedBy = [ "multi-user.target" ];
        requires = [ "test-wireguard-peer.service" ];
        after = [ "test-wireguard-peer.service" ];
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${pkgs.python3}/bin/python -m http.server 18080 --bind 10.71.216.232 --directory /etc";
        };
      };
      systemd.services.test-tunnel-udp = {
        wantedBy = [ "multi-user.target" ];
        requires = [ "test-wireguard-peer.service" ];
        after = [ "test-wireguard-peer.service" ];
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${pkgs.python3}/bin/python ${
            pkgs.writers.writePython3 "vpn_udp_echo.py" {
              flakeIgnore = [
                "E501"
                "W503"
              ];
            } (builtins.readFile ./scripts/vpn_udp_echo.py)
          }";
        };
      };
      systemd.services.test-connect-http = {
        wantedBy = [ "multi-user.target" ];
        requires = [ "test-wireguard-peer.service" ];
        after = [ "test-wireguard-peer.service" ];
        serviceConfig = {
          DynamicUser = true;
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          ExecStart = "${pkgs.python3}/bin/python -m http.server 443 --bind 10.71.216.232 --directory /etc";
        };
      };
      systemd.services.test-cleartext-http = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${pkgs.python3}/bin/python -m http.server 18081 --bind 0.0.0.0 --directory /etc";
        };
      };

      environment.systemPackages = with pkgs; [
        curl
        dig
        iproute2
        iputils
        nftables
        python3
        tcpdump
        util-linux
        wireguard-tools
      ];
      environment.etc."vpn-test-addresses".text = builtins.toJSON {
        inherit hostAddress namespaceAddress;
        inherit (namespace.hostLink) hostIf nsIf;
      };
    };

  nodes.lan = { pkgs, lib, ... }: {
    system.stateVersion = "26.05";
    networking.useDHCP = false;
    networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
      {
        address = "192.168.1.2";
        prefixLength = 24;
      }
    ];
    environment.systemPackages = [ pkgs.curl ];
  };

  testScript = builtins.readFile ./scripts/vpn_namespace_test.py;
}
