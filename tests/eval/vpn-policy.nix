{
  evaluate,
  lib,
  pkgs,
}:
let
  fixture = {
    imports = [ ../../examples/media-server.nix ];
    homelab = {
      indexerProxy = {
        enable = true;
        passwordFile = "/run/secrets/indexer-proxy-password";
      };
      apps = {
        sabnzbd = {
          enable = true;
          vpn.enable = true;
        };
        nzbget = {
          enable = true;
          vpn.enable = true;
        };
      };
    };
  };
  c = (evaluate fixture).config;
  restricted =
    (evaluate {
      imports = [ fixture ];
      services.vpnConfinement.namespaces.vpnapps = {
        securityProfile = "highAssurance";
        egress.allowedCidrs = [ "198.51.100.0/24" ];
      };
    }).config;
  invalidPrivateKey =
    (evaluate {
      imports = [ fixture ];
      homelab.vpn.interface.privateKeyFile = lib.mkForce "/nix/store/public-invalid-key";
    }).config;
  invalidPresharedKey =
    (evaluate {
      imports = [ fixture ];
      homelab.vpn.peer.presharedKeyFile = "/run/keys/client:psk";
    }).config;
  invalidEndpoint =
    (evaluate {
      imports = [ fixture ];
      homelab.vpn.peer.endpointHost = lib.mkForce "vpn.example";
    }).config;
  ns = c.services.vpnConfinement.namespaces.${c.homelab.vpn.namespace.name};
  units = map (name: c.systemd.services.${name}) [
    "qbittorrent"
    "sabnzbd"
    "nzbget"
    "microsocks"
  ];
  emptyCapabilities = value: value == "" || value == [ ];
  contracts = {
    # Force generated unit definitions too: assertions alone miss conflicting
    # sandbox defaults on optional confined applications.
    generatedUnits = builtins.deepSeq (map (unit: [
      c.systemd.units.${unit.name}.text
      restricted.systemd.units.${unit.name}.text
    ]) units) true;
    validConfiguration = lib.all (a: a.assertion) c.assertions;
    # Force unit rendering: assertions alone leave conflicting sandbox options
    # unevaluated, so an apparently valid policy can still fail to build.
    renderedConsumerUnits =
      lib.all (name: builtins.stringLength c.systemd.units."${name}.service".text > 0)
        [
          "qbittorrent"
          "sabnzbd"
          "nzbget"
          "microsocks"
        ];
    strictResolver = ns.dns.mode == "strict" && !ns.dns.allowHostResolverIPC;
    literalPinnedEndpoint = ns.wireguard.endpointPinning.enable && !ns.wireguard.allowHostnameEndpoints;
    runtimeKeysOnly = !ns.wireguard.allowInsecureKeyMaterial;
    runtimePrivateKeyPathRejected = lib.any (a: !a.assertion) invalidPrivateKey.assertions;
    runtimePresharedKeyPathRejected = lib.any (a: !a.assertion) invalidPresharedKey.assertions;
    hostnameEndpointRejected = lib.any (a: !a.assertion) invalidEndpoint.assertions;
    dynamicPeersInsideTunnel = ns.egress.mode == "allowAllTunnel";
    destinationRestrictionsCompose =
      restricted.services.vpnConfinement.namespaces.vpnapps.egress.mode == "allowList"
      && lib.all (a: a.assertion) restricted.assertions;
    enforcedServicesWithoutExceptions =
      ns.servicePolicy == "enforced"
      && lib.all (
        unit:
        !unit.vpn.allowUnsafeCapabilities
        && !unit.vpn.allowPrivilegedCommands
        && !unit.vpn.allowHostSockets
        && !unit.vpn.allowRootInHighAssurance
      ) units;
    noCapabilities = lib.all (
      unit:
      emptyCapabilities unit.serviceConfig.CapabilityBoundingSet
      && emptyCapabilities unit.serviceConfig.AmbientCapabilities
      && unit.serviceConfig.NoNewPrivileges
    ) units;
    dedicatedServiceUsers = lib.all (
      unit:
      let
        user = unit.serviceConfig.User or "";
      in
      builtins.isString user
      && !(builtins.elem user [
        ""
        "root"
        "0"
      ])
    ) units;
    upstreamNamespaceAttachment = lib.all (
      unit:
      unit.vpn.enable
      && unit.serviceConfig.NetworkNamespacePath == "/run/netns/${c.homelab.vpn.namespace.name}"
    ) units;
    ipv6DisabledWithoutTunnelAddress = ns.ipv6.mode == "disable";
    noProviderInboundPorts = ns.ingress.fromTunnel.tcp == [ ] && ns.ingress.fromTunnel.udp == [ ];
    onlyDeclaredHostPorts =
      lib.sort builtins.lessThan ns.publishToHost.tcp == [
        1080
        6789
        8080
        8081
      ];
    hostFirewallClosed =
      c.networking.firewall.enable
      && c.networking.firewall.allowedTCPPorts == [ ]
      && c.networking.firewall.allowedUDPPorts == [ ]
      && c.networking.firewall.allowedTCPPortRanges == [ ]
      && c.networking.firewall.allowedUDPPortRanges == [ ]
      && lib.all (
        interface:
        interface.allowedTCPPorts == [ ]
        && interface.allowedUDPPorts == [ ]
        && interface.allowedTCPPortRanges == [ ]
        && interface.allowedUDPPortRanges == [ ]
      ) (lib.attrValues c.networking.firewall.interfaces);
    managersStayOnHost =
      !c.systemd.services.sonarr.vpn.enable && !c.systemd.services.prowlarr.vpn.enable;
    downloaderLibraryReadOnly = builtins.elem c.homelab.storage.libraryDir c.systemd.services.qbittorrent.serviceConfig.BindReadOnlyPaths;
  };
in
assert lib.assertMsg (lib.all (x: x) (lib.attrValues contracts))
  "Failed VPN policy contracts: ${
    lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: passed: !passed) contracts))
  }";
pkgs.writeText "homelab-vpn-policy.json" (builtins.toJSON contracts)
