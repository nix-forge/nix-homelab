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
      imports = [ homelabModule ];
      system.stateVersion = "26.05";
      virtualisation.memorySize = 1536;

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
              allowedUDPPorts = [ 53 ];
            };
            ${namespace.hostLink.hostIf}.allowedTCPPorts = [ 18081 ];
          };
        };
      };
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
      services.resolved.enable = true;

      homelab.storage.enable = true;
      homelab.indexerProxy.enable = true;
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
        script = ''
          set -eu
          umask 077
          mkdir -p /run/wg-test
          printf '%s\n' 'qE43SrN52JGV9FYU5i7jp5zCq+8osxyXORZfS5faf3s=' > /run/wg-test/client.key
          printf '%s\n' 'wOXXEHK/pVYgJSj/mU05R2kCz+bhawfV0TttYud+zk8=' > /run/wg-test/peer.key
          ip link add wg-test-peer type wireguard
          ip address add 10.71.216.232/32 dev wg-test-peer
          ip address add 10.71.216.233/32 dev wg-test-peer
          wg set wg-test-peer private-key /run/wg-test/peer.key listen-port 51821 \
            peer "$(wg pubkey < /run/wg-test/client.key)" allowed-ips 10.71.216.231/32
          ip link set wg-test-peer up
          ip route add 10.71.216.231/32 dev wg-test-peer
        '';
        postStop = ''
          ${pkgs.iproute2}/bin/ip link del wg-test-peer 2>/dev/null || true
        '';
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

  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("qbittorrent.service")
    machine.wait_for_unit("dnsmasq.service")
    machine.wait_for_unit("tinyproxy.service")
    machine.wait_for_unit("test-tunnel-http.service")
    machine.wait_for_unit("test-cleartext-http.service")
    machine.wait_for_unit("test-connect-http.service")
    lan.wait_for_unit("multi-user.target")
    addresses = json.loads(machine.succeed("cat /etc/vpn-test-addresses"))
    namespace_address = addresses["namespaceAddress"]
    host_address = addresses["hostAddress"]
    ns_if = addresses["nsIf"]
    host_if = addresses["hostIf"]
    web_url = f"http://{namespace_address}:8081/"
    tunnel_url = "http://10.71.216.232:18080/hostname"

    with subtest("The real tunnel carries requests and completes a handshake"):
        machine.wait_until_succeeds(f"ip netns exec vpnapps curl -fsS --max-time 3 {tunnel_url}")
        machine.succeed("ip netns exec vpnapps wg show wg0 latest-handshakes | awk '$2 > 0 { ok = 1 } END { exit !ok }'")
        machine.wait_until_succeeds(f"curl --noproxy invalid.example -x http://{namespace_address}:8888 -fsS --max-time 3 {tunnel_url}")
        machine.succeed("wg show wg-test-peer latest-handshakes | awk '$2 > 0 { ok = 1 } END { exit !ok }'")
        machine.succeed("ip netns exec vpnapps wg show wg0 transfer | awk '$2 > 0 && $3 > 0 { ok = 1 } END { exit !ok }'")

    with subtest("Proxy hostname resolution and CONNECT policy"):
        # Exercise CONNECT443 with a plain HTTP fixture inside the tunnel; TLS
        # verification remains the requesting application's responsibility.
        machine.wait_until_succeeds(f"curl --proxytunnel --noproxy invalid.example -x http://{namespace_address}:8888 -fsS --max-time 3 http://vpn-fixture.test:443/hostname")
        machine.fail(f"curl --proxytunnel --noproxy invalid.example -x http://{namespace_address}:8888 -f --max-time 3 {tunnel_url}")

    with subtest("The proxy does not log indexer query credentials"):
        machine.succeed(f"curl --noproxy invalid.example -x http://{namespace_address}:8888 -fsS --max-time 3 {tunnel_url}?apikey=homelab-query-secret-fixture")
        journal = machine.succeed("journalctl -u tinyproxy.service --no-pager")
        assert "homelab-query-secret-fixture" not in journal, journal

    with subtest("qBittorrent's web interface is available only from the host"):
        machine.wait_until_succeeds(f"curl -fsS --max-time 3 {web_url}")
        lan.wait_until_succeeds("curl -fsS --max-time 3 http://192.168.1.1:18081/hostname")
        lan.succeed(f"ip route add {namespace_address}/32 via 192.168.1.1")
        lan.fail(f"curl -f --max-time 3 {web_url}")
        lan.fail(f"curl --noproxy invalid.example -x http://{namespace_address}:8888 -f --max-time 3 {tunnel_url}")
        lan.fail("curl -f --max-time 3 http://192.168.1.1:8081/")
        machine.fail(f"ip netns exec vpnapps curl -f --max-time 3 http://{host_address}:18081/")
        machine.succeed("systemctl show -p NetworkNamespacePath --value qbittorrent.service | grep -Fx /run/netns/vpnapps")

    with subtest("The service resolves DNS through the tunnel and blocks other resolvers"):
        pid = machine.succeed("systemctl show -p MainPID --value qbittorrent.service").strip()
        service_exec = f"nsenter --target {pid} --mount --net --"
        resolver = machine.succeed(f"{service_exec} cat /etc/resolv.conf")
        assert "nameserver 10.71.216.232" in resolver, resolver
        assert "127.0.0.53" not in resolver, resolver
        machine.wait_until_succeeds(f"{service_exec} getent ahostsv4 vpn-fixture.test | grep -F 10.71.216.232")
        machine.succeed("ip netns exec vpnapps dig +time=1 +tries=1 @10.71.216.232 vpn-fixture.test A | grep -F 10.71.216.232")
        machine.succeed("dig +time=1 +tries=1 @10.71.216.233 vpn-fixture.test A | grep -F 10.71.216.232")
        machine.fail("ip netns exec vpnapps dig +time=1 +tries=1 @10.71.216.233 vpn-fixture.test A")
        machine.fail("ip netns exec vpnapps dig +tcp +time=1 +tries=1 @10.71.216.233 vpn-fixture.test A")
        inaccessible = machine.succeed("systemctl show -p InaccessiblePaths --value qbittorrent.service")
        assert "/run/nscd" in inaccessible and "/run/dbus/system_bus_socket" in inaccessible, inaccessible
        machine.succeed("ip netns exec vpnapps sysctl -n net.ipv6.conf.all.disable_ipv6 | grep -Fx 1")

    with subtest("Tunnel loss never falls back to cleartext, even with an injected route"):
        machine.succeed("ip -n vpnapps link set wg0 down")
        machine.succeed(f"ip -n vpnapps route replace default via {host_address} dev {ns_if}")
        machine.succeed(f"tcpdump -i {host_if} -n -U -w /tmp/cleartext.pcap 'tcp port 18081' >/tmp/tcpdump.log 2>&1 & echo $! > /tmp/tcpdump.pid")
        machine.wait_until_succeeds("grep -q 'listening on' /tmp/tcpdump.log")
        machine.fail("ip netns exec vpnapps curl -f --max-time 3 http://192.168.1.1:18081/hostname")
        machine.fail(f"ip netns exec vpnapps curl -f --max-time 3 http://{host_address}:18081/hostname")
        machine.fail(f"ip netns exec vpnapps curl -f --max-time 3 {tunnel_url}")
        machine.fail(f"curl --noproxy invalid.example -x http://{namespace_address}:8888 -f --max-time 3 {tunnel_url}")
        machine.fail("ip netns exec vpnapps curl -g -f --max-time 3 http://[2001:db8::1]:18081/")
        machine.succeed("kill -INT $(cat /tmp/tcpdump.pid)")
        machine.wait_until_succeeds("grep -q 'packets captured' /tmp/tcpdump.log")
        packets = machine.succeed("tcpdump -n -r /tmp/cleartext.pcap 2>/dev/null").strip()
        assert not packets, f"Cleartext packets escaped the namespace: {packets}"
        machine.succeed(f"curl -fsS --max-time 3 {web_url}")
        machine.succeed("ip -n vpnapps link set wg0 up")
        machine.succeed("ip -n vpnapps route replace default dev wg0")
        machine.wait_until_succeeds(f"ip netns exec vpnapps curl -fsS --max-time 3 {tunnel_url}")

    with subtest("Stopping WireGuard stops consumers and tears down the namespace; a restart recovers"):
        machine.succeed("systemctl stop wireguard-wg0.service")
        machine.wait_until_succeeds("! systemctl is-active --quiet qbittorrent.service")
        machine.wait_until_succeeds("test ! -e /run/netns/vpnapps")
        machine.fail(f"curl -f --max-time 3 {web_url}")
        machine.succeed("systemctl start qbittorrent.service")
        machine.wait_for_unit("wireguard-wg0.service")
        machine.wait_for_unit("qbittorrent.service")
        machine.wait_until_succeeds(f"curl -fsS --max-time 3 {web_url}")
        machine.wait_until_succeeds(f"ip netns exec vpnapps curl -fsS --max-time 3 {tunnel_url}")
        machine.wait_until_succeeds("ip netns exec vpnapps dig +time=1 +tries=1 @10.71.216.232 vpn-fixture.test A | grep -F 10.71.216.232")
  '';
}
