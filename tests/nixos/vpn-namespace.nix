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
      };
      homelab.apps.prowlarr = {
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
      systemd.services.test-tunnel-udp = {
        wantedBy = [ "multi-user.target" ];
        requires = [ "test-wireguard-peer.service" ];
        after = [ "test-wireguard-peer.service" ];
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${pkgs.python3}/bin/python ${pkgs.writeText "vpn-udp-echo.py" ''
            import socket
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                sock.bind(("10.71.216.232", 19000))
                while True:
                    data, peer = sock.recvfrom(4096)
                    sock.sendto(data, peer)
          ''}";
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

  testScript = ''
    import json
    import shlex
    import time

    start_all()
    consumers = ["qbittorrent", "sabnzbd", "nzbget", "prowlarr", "microsocks"]
    for service in consumers:
        machine.wait_for_unit(f"{service}.service")
    machine.wait_for_unit("dnsmasq.service")
    machine.wait_for_unit("microsocks.service")
    machine.wait_for_unit("test-tunnel-http.service")
    machine.wait_for_unit("test-tunnel-udp.service")
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
    proxy_url = f"socks5h://prowlarr:fixture-password@{namespace_address}:1080"

    def service_exec(service):
        # SABnzbd intentionally uses Type=forking with GuessMainPID=no.
        # Inspect every process in the unit cgroup instead of trusting MainPID.
        group = machine.succeed(f"systemctl show -p ControlGroup --value {service}.service").strip()
        assert group.startswith("/system.slice/"), (service, group)
        machine.succeed(f"systemctl show -p Delegate --value {service}.service | grep -Fx no")
        pids = [int(pid) for pid in machine.succeed(f"cat /sys/fs/cgroup{group}/cgroup.procs").split()]
        assert pids, f"{service} has no running processes"
        expected = machine.succeed("ip netns exec vpnapps readlink /proc/self/ns/net").strip()
        for pid in pids:
            status = dict(line.split(":", 1) for line in machine.succeed(f"cat /proc/{pid}/status").splitlines() if ":" in line)
            for capability in ["CapEff", "CapPrm", "CapBnd", "CapAmb"]:
                assert int(status[capability].strip(), 16) == 0, (service, capability, status[capability])
            assert status["NoNewPrivs"].strip() == "1", (service, status)
            assert status["Uid"].split()[1] != "0", f"{service} runs as root"
            actual = machine.succeed(f"readlink /proc/{pid}/ns/net").strip()
            assert actual == expected, f"{service} escaped vpnapps: {actual} != {expected}"
        main_pid = int(machine.succeed(f"systemctl show -p MainPID --value {service}.service"))
        # In this fresh VM the oldest remaining PID is the fallback daemon.
        # Prefer systemd's tracked process when available, rather than a worker.
        target_pid = main_pid if main_pid in pids else min(pids)
        return f"nsenter --target {target_pid} --mount --net --"

    def assert_consumer_stopped(service):
        machine.wait_until_succeeds(f"! systemctl is-active --quiet {service}.service")
        group = machine.succeed(f"systemctl show -p ControlGroup --value {service}.service").strip()
        if group:
            assert group.startswith("/system.slice/"), (service, group)
            machine.succeed(f"test ! -e /sys/fs/cgroup{group}/cgroup.events || grep -Fx 'populated 0' /sys/fs/cgroup{group}/cgroup.events")

    def start_capture(label):
        # All outbound IPv4/IPv6, including packets with an unexpected source IP.
        # ARP is link maintenance, and carries no workload IP payload.
        machine.succeed(f"tcpdump --immediate-mode -i {host_if} -Q in -nn -U -w /tmp/{label}.pcap '(ip or ip6)' >/tmp/{label}.log 2>&1 & echo $! > /tmp/{label}.pid")
        machine.wait_until_succeeds(f"grep -q 'listening on' /tmp/{label}.log")

    def finish_capture(label):
        time.sleep(1)
        machine.succeed(f"kill -INT $(cat /tmp/{label}.pid)")
        machine.wait_until_succeeds(f"grep -E 'packets? captured' /tmp/{label}.log || (cat /tmp/{label}.log; false)", timeout=10)
        stats = machine.succeed(f"cat /tmp/{label}.log")
        assert "0 packets dropped by kernel" in stats.splitlines(), stats
        machine.copy_from_machine(f"/tmp/{label}.pcap")
        return machine.succeed(f"tcpdump -nn -r /tmp/{label}.pcap 2>/dev/null").strip()

    def blocked_probes(label):
        # Do not make host UI/proxy requests during capture: their explicitly
        # permitted replies would be outbound packets on the same interface.
        time.sleep(2)
        start_capture(label)
        for service in consumers:
            execute = service_exec(service)
            for destination in [host_address, "192.168.1.1", "192.168.1.2", "198.51.100.1"]:
                machine.fail(f"{execute} curl --noproxy '*' -fsS --connect-timeout 1 --max-time 1 http://{destination}:18081/")
                for transport in ["", "+tcp"]:
                    machine.fail(f"{execute} dig {transport} +time=1 +tries=1 @{destination} {label}.vpn-fixture.test A")
            # UDP send success says nothing about delivery. The packet capture
            # is the assertion for peer, QUIC, DNS-over-QUIC and multicast probes.
            destinations = [(host_address, 19000), ("198.51.100.1", 443), ("198.51.100.1", 853), ("239.255.255.250", 1900), ("224.0.0.251", 5353)]
            code = "\n".join([
                "import errno, socket",
                f"for address, port in {destinations!r}:",
                "    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:",
                "        try:",
                f"            sock.sendto(b'vpn-leak-{label}', (address, port))",
                "        except OSError as error:",
                "            if error.errno not in (errno.EPERM, errno.EACCES):",
                "                raise",
            ])
            machine.succeed(f"{execute} python3 -c {shlex.quote(code)}")
            for port in [443, 853]:
                machine.fail(f"{execute} curl --noproxy '*' -fsS --max-time 1 https://{host_address}:{port}/")
            machine.fail(f"{execute} ping -c 1 -W 1 {host_address}")
            # A published UI source port must not grant permission to initiate
            # a new host connection, even though UI replies are allowed.
            bind_control = "import socket; s = socket.socket(); s.bind(('10.71.216.231', 8081)); s.close()"
            machine.succeed(f"{execute} python3 -c {shlex.quote(bind_control)}")
            machine.fail(f"{execute} curl --noproxy '*' --interface 10.71.216.231 --local-port 8081 -fsS --max-time 1 http://{host_address}:18081/")
            # ProcSubset=pid can hide /proc/sys in an application's mount
            # namespace. service_exec already verified its network namespace.
            machine.succeed("ip netns exec vpnapps sysctl -n net.ipv6.conf.all.disable_ipv6 | grep -Fx 1")
            machine.fail(f"{execute} curl --noproxy '*' -g -fsS --max-time 1 http://[2001:db8::1]:18081/")
        packets = finish_capture(label)
        assert not packets, f"{label}: packets escaped to the host link: {packets}"

    def assert_consumer_ready(service):
        execute = service_exec(service)
        resolver = machine.succeed(f"{execute} cat /etc/resolv.conf")
        servers = [line.split()[1] for line in resolver.splitlines() if line.startswith("nameserver ")]
        assert servers == ["10.71.216.232"], (service, resolver)
        machine.wait_until_succeeds(f"{execute} getent ahostsv4 vpn-fixture.test | grep -F 10.71.216.232")
        machine.wait_until_succeeds(f"{execute} curl --noproxy '*' -fsS --max-time 3 {tunnel_url}")
        for path in ["/run/nscd/socket", "/run/dbus/system_bus_socket", "/run/systemd/resolve/io.systemd.Resolve"]:
            connect = f"import socket; s = socket.socket(socket.AF_UNIX); s.settimeout(1); s.connect('{path}')"
            machine.fail(f"{execute} python3 -c {shlex.quote(connect)}")

    with subtest("Every opted-in consumer runs in the VPN namespace with tunnel DNS"):
        machine.wait_for_unit("systemd-resolved.service")
        socket_control = "import socket; s = socket.socket(socket.AF_UNIX); s.connect('/run/systemd/resolve/io.systemd.Resolve'); s.close()"
        machine.succeed(f"python3 -c {shlex.quote(socket_control)}")
        for service in consumers:
            assert_consumer_ready(service)

    with subtest("The leak detector observes a deliberately permitted UDP leak"):
        # Mutation control: temporarily permit exactly one disposable UDP probe.
        machine.succeed(f"ip netns exec vpnapps nft insert rule inet vpnc output ip daddr {host_address} udp dport 19000 counter accept comment leak-detector-control")
        rules = json.loads(machine.succeed("ip netns exec vpnapps nft -j -a list chain inet vpnc output"))
        handle = next(item["rule"]["handle"] for item in rules["nftables"] if item.get("rule", {}).get("comment") == "leak-detector-control")
        try:
            start_capture("positive-control")
            code = f"import socket; socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(b'control', ('{host_address}', 19000))"
            machine.succeed(f"ip netns exec vpnapps python3 -c {shlex.quote(code)}")
            packets = finish_capture("positive-control")
            assert f"{host_address}.19000" in packets, packets
        finally:
            machine.succeed(f"ip netns exec vpnapps nft delete rule inet vpnc output handle {handle}")

    with subtest("Healthy tunnel rejects direct host-link traffic for every consumer"):
        # More-specific routes model accidental routes installed by other software.
        for destination in ["192.168.1.1", "192.168.1.2", "198.51.100.1", "239.255.255.250", "224.0.0.251"]:
            machine.succeed(f"ip -n vpnapps route replace {destination}/32 via {host_address} dev {ns_if}")
        blocked_probes("healthy")

    with subtest("The real tunnel carries requests and completes a handshake"):
        machine.wait_until_succeeds(f"ip netns exec vpnapps curl -fsS --max-time 3 {tunnel_url}", timeout=30)
        machine.succeed("ip netns exec vpnapps wg show wg0 latest-handshakes | awk '$2 > 0 { ok = 1 } END { exit !ok }'")
        machine.wait_until_succeeds(f"curl --proxy {proxy_url} -fsS --max-time 3 {tunnel_url}")
        machine.succeed("wg show wg-test-peer latest-handshakes | awk '$2 > 0 { ok = 1 } END { exit !ok }'")
        machine.succeed("ip netns exec vpnapps wg show wg0 transfer | awk '$2 > 0 && $3 > 0 { ok = 1 } END { exit !ok }'")

    with subtest("Proxy authentication and tunnel-side hostname resolution"):
        machine.wait_until_succeeds(f"curl --proxy {proxy_url} -fsS --max-time 3 http://vpn-fixture.test:18080/hostname")
        machine.fail(f"curl --proxy socks5h://{namespace_address}:1080 -f --max-time 3 {tunnel_url}")

    with subtest("The proxy does not log indexer query credentials"):
        machine.succeed(f"curl --proxy {proxy_url} -fsS --max-time 3 {tunnel_url}?apikey=homelab-query-secret-fixture")
        journal = machine.succeed("journalctl -u microsocks.service --no-pager")
        assert "homelab-query-secret-fixture" not in journal, journal

    with subtest("qBittorrent's web interface is available only from the host"):
        machine.wait_until_succeeds(f"curl -fsS --max-time 3 {web_url}")
        lan.wait_until_succeeds("curl -fsS --max-time 3 http://192.168.1.1:18081/hostname")
        lan.succeed(f"ip route add {namespace_address}/32 via 192.168.1.1")
        lan.fail(f"curl -f --max-time 3 {web_url}")
        lan.fail(f"curl --proxy socks5h://prowlarr:fixture-password@{namespace_address}:1080 -f --max-time 3 {tunnel_url}")
        lan.fail("curl -f --max-time 3 http://192.168.1.1:8081/")
        machine.fail(f"ip netns exec vpnapps curl -f --max-time 3 http://{host_address}:18081/")
        machine.succeed("systemctl show -p NetworkNamespacePath --value qbittorrent.service | grep -Fx /run/netns/vpnapps")

    with subtest("The service resolves DNS through the tunnel and blocks other resolvers"):
        pid = machine.succeed("systemctl show -p MainPID --value qbittorrent.service").strip()
        execute = f"nsenter --target {pid} --mount --net --"
        resolver = machine.succeed(f"{execute} cat /etc/resolv.conf")
        assert "nameserver 10.71.216.232" in resolver, resolver
        assert "127.0.0.53" not in resolver, resolver
        machine.wait_until_succeeds(f"{execute} getent ahostsv4 vpn-fixture.test | grep -F 10.71.216.232")
        machine.succeed("ip netns exec vpnapps dig +short +time=1 +tries=1 @10.71.216.232 vpn-fixture.test A | grep -Fx 10.71.216.232")
        machine.succeed("ip netns exec vpnapps dig +tcp +short +time=1 +tries=1 @10.71.216.232 vpn-fixture.test A | grep -Fx 10.71.216.232")
        machine.succeed("dig +short +time=1 +tries=1 @10.71.216.233 vpn-fixture.test A | grep -Fx 10.71.216.232")
        machine.fail("ip netns exec vpnapps dig +time=1 +tries=1 @10.71.216.233 vpn-fixture.test A")
        machine.fail("ip netns exec vpnapps dig +tcp +time=1 +tries=1 @10.71.216.233 vpn-fixture.test A")
        inaccessible = machine.succeed("systemctl show -p InaccessiblePaths --value qbittorrent.service")
        assert "/run/nscd" in inaccessible and "/run/dbus/system_bus_socket" in inaccessible, inaccessible
        machine.succeed("ip netns exec vpnapps sysctl -n net.ipv6.conf.all.disable_ipv6 | grep -Fx 1")

    with subtest("An established UDP flow continues probing through failure and recovery"):
        # Keep the same connected socket and source port through route changes.
        # This catches an established-flow exception that ignores the output link.
        code = "\n".join([
            "import socket, time",
            "sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)",
            "sock.settimeout(0.2)",
            "sock.connect(('10.71.216.232', 19000))",
            "sequence = 0",
            "while True:",
            "    sequence += 1",
            "    payload = str(sequence).encode()",
            "    try:",
            "        sock.send(payload)",
            "        deadline = time.monotonic() + 0.2",
            "        while time.monotonic() < deadline:",
            "            if sock.recv(4096) == payload:",
            "                print(sequence, flush=True)",
            "                break",
            "    except OSError:",
            "        pass",
            "    time.sleep(0.1)",
        ])
        machine.succeed(f"ip netns exec vpnapps python3 -u -c {shlex.quote(code)} >/tmp/udp-flow.log 2>&1 & echo $! > /tmp/udp-flow.pid")
        machine.wait_until_succeeds("grep -E '^[0-9]+$' /tmp/udp-flow.log")

    with subtest("A silent peer failure keeps consumers confined while WireGuard stays up"):
        machine.succeed("nft add table inet test_peer_outage")
        machine.succeed("nft 'add chain inet test_peer_outage input { type filter hook input priority -100; policy accept; }'")
        machine.succeed("nft add rule inet test_peer_outage input iifname lo udp dport 51821 counter drop")
        for service in consumers:
            machine.fail(f"{service_exec(service)} curl --noproxy '*' -fsS --max-time 2 {tunnel_url}")
            machine.fail(f"{service_exec(service)} dig +time=1 +tries=1 @10.71.216.232 outage.vpn-fixture.test A")
        blocked_probes("silent-peer-failure")
        machine.fail(f"curl --proxy {proxy_url} -f --max-time 3 {tunnel_url}")
        # Discard the proxy's pending request before the next capture. Its
        # eventual host reply is permitted traffic, not an outbound leak.
        machine.succeed("systemctl restart microsocks.service")
        machine.wait_for_unit("microsocks.service")
        outage_rules = json.loads(machine.succeed("nft -j list table inet test_peer_outage"))
        dropped = [
            expression["counter"]["packets"]
            for item in outage_rules["nftables"] if "rule" in item
            for expression in item["rule"]["expr"] if "counter" in expression
        ]
        assert sum(dropped) > 0, "The simulated provider outage did not intercept transport packets"
        machine.succeed("nft delete table inet test_peer_outage")
        machine.wait_until_succeeds(f"ip netns exec vpnapps curl -fsS --max-time 3 {tunnel_url}", timeout=30)

    with subtest("Tunnel loss never falls back to cleartext, even with an injected default route"):
        time.sleep(2)
        start_capture("fallback-transition")
        machine.succeed("ip -n vpnapps link set wg0 down")
        machine.succeed(f"ip -n vpnapps route replace default via {host_address} dev {ns_if}")
        blocked_probes("forced-fallback")
        # The approved resolver and tunnel destination now route toward the host.
        start_capture("resolver-fallback")
        for service in consumers:
            execute = service_exec(service)
            machine.fail(f"{execute} curl --noproxy '*' -fsS --max-time 2 {tunnel_url}")
            for transport in ["", "+tcp"]:
                machine.fail(f"{execute} dig {transport} +time=1 +tries=1 @10.71.216.232 fallback.vpn-fixture.test A")
            machine.fail(f"{execute} getent ahostsv4 uncached-fallback.vpn-fixture.test")
        assert not finish_capture("resolver-fallback"), "Tunnel traffic or DNS escaped through the fallback route"
        machine.succeed("kill -0 $(cat /tmp/udp-flow.pid)")
        assert not finish_capture("fallback-transition"), "Traffic escaped during tunnel or route changes"
        machine.fail(f"curl --proxy {proxy_url} -f --max-time 3 {tunnel_url}")
        # Discard the proxy's pending request before the next capture. Its
        # eventual host reply is permitted traffic, not an outbound leak.
        machine.succeed("systemctl restart microsocks.service")
        machine.wait_for_unit("microsocks.service")
        machine.succeed(f"curl -fsS --max-time 3 {web_url}")
        time.sleep(2)
        start_capture("recovery-transition")
        replies = int(machine.succeed("grep -cE '^[0-9]+$' /tmp/udp-flow.log"))
        machine.succeed("ip -n vpnapps link set wg0 up")
        machine.succeed("ip -n vpnapps route replace default dev wg0")
        machine.wait_until_succeeds(f"ip netns exec vpnapps curl -fsS --max-time 3 {tunnel_url}", timeout=30)
        blocked_probes("recovered")
        machine.wait_until_succeeds(f"test $(grep -cE '^[0-9]+$' /tmp/udp-flow.log) -gt {replies}")
        machine.succeed("kill -0 $(cat /tmp/udp-flow.pid)")
        assert not finish_capture("recovery-transition"), "Traffic escaped while restoring the tunnel route"
        machine.succeed("kill $(cat /tmp/udp-flow.pid)")

    with subtest("Stopping WireGuard stops consumers and tears down the namespace; a restart recovers"):
        machine.succeed("systemctl stop wireguard-wg0.service")
        for service in consumers:
            assert_consumer_stopped(service)
        machine.wait_until_succeeds("test ! -e /run/netns/vpnapps")
        machine.fail(f"curl -f --max-time 3 {web_url}")
        machine.succeed("systemctl start " + " ".join(f"{service}.service" for service in consumers))
        machine.wait_for_unit("wireguard-wg0.service")
        machine.wait_for_unit("qbittorrent.service")
        machine.wait_until_succeeds(f"curl -fsS --max-time 3 {web_url}")
        machine.wait_until_succeeds(f"ip netns exec vpnapps curl -fsS --max-time 3 {tunnel_url}", timeout=30)
        machine.wait_until_succeeds("ip netns exec vpnapps dig +short +time=1 +tries=1 @10.71.216.232 vpn-fixture.test A | grep -Fx 10.71.216.232")
        for service in consumers:
            machine.wait_for_unit(f"{service}.service")
            assert_consumer_ready(service)

    with subtest("Missing runtime key prevents consumers from starting; restoring it recovers"):
        machine.succeed("systemctl stop wireguard-wg0.service")
        for service in consumers:
            assert_consumer_stopped(service)
        machine.succeed("mv /run/wg-test/client.key /run/wg-test/client.key.saved")
        try:
            machine.fail("systemctl start " + " ".join(f"{service}.service" for service in consumers))
            for service in consumers:
                assert_consumer_stopped(service)
        finally:
            machine.succeed("mv /run/wg-test/client.key.saved /run/wg-test/client.key")
        machine.succeed("systemctl reset-failed")
        machine.succeed("systemctl start " + " ".join(f"{service}.service" for service in consumers))
        for service in consumers:
            machine.wait_for_unit(f"{service}.service")
            assert_consumer_ready(service)
  '';
}
