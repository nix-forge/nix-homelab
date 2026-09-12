{ lib, config, ... }:
let
  inherit (lib)
    hasInfix
    hasPrefix
    hasSuffix
    mkEnableOption
    mkIf
    mkOption
    mkRemovedOptionModule
    optionals
    removePrefix
    removeSuffix
    types
    ;

  cfg = config.homelab.vpn;
  useIPv4 = cfg.interface.addressIPv4 != null;
  useIPv6 = cfg.interface.addressIPv6 != null;
  namespace = config.services.vpnConfinement.namespaces.${cfg.namespace.name};

  # Format IPv6 endpoints; vpn-confinement owns IP and endpoint validation.
  rawEndpoint = if cfg.peer.endpointHost == null then "" else cfg.peer.endpointHost;
  endpointHost =
    if hasPrefix "[" rawEndpoint && hasSuffix "]" rawEndpoint then
      removeSuffix "]" (removePrefix "[" rawEndpoint)
    else
      rawEndpoint;
  endpoint =
    if hasInfix ":" endpointHost then
      "[${endpointHost}]:${toString cfg.peer.endpointPort}"
    else
      "${endpointHost}:${toString cfg.peer.endpointPort}";

  removeNamespaceOption =
    path: message:
    mkRemovedOptionModule (
      [
        "homelab"
        "vpn"
        "namespace"
      ]
      ++ path
    ) message;
in
{
  imports = [
    (removeNamespaceOption [ "path" ] ''
      vpn-confinement owns namespace attachment. Set systemd.services.<name>.vpn =
      { enable = true; namespace = config.homelab.vpn.namespace.name; }.
    '')
    (removeNamespaceOption [ "resolvConfPath" ] ''
      vpn-confinement generates and mounts the resolver file for each VPN service.
      Configure homelab.vpn.interface.dns instead.
    '')
    (removeNamespaceOption [ "serviceHardening" ] ''
      vpn-confinement applies service hardening. Configure
      systemd.services.<name>.vpn.hardeningProfile and serviceConfig as needed.
    '')
    (removeNamespaceOption [ "veth" ] ''
      vpn-confinement owns the host link. For explicit network allocation, use
      services.vpnConfinement.namespaces.<name>.hostLink.subnetIPv4, hostIf and nsIf.
      Read config.homelab.vpn.namespace.bindAddress for the service bind address.
    '')
    (removeNamespaceOption [ "hostIngressPorts" "udp" ] ''
      vpn-confinement publishes only TCP ports to the host. Remove this option.
      homelab.vpn.inboundPorts.udp allows traffic from the VPN tunnel, not the host.
    '')
  ];

  options.homelab.vpn = {
    enable = mkEnableOption "WireGuard confinement for selected homelab services";

    namespace = {
      name = mkOption {
        type = types.str;
        default = "vpnapps";
        description = "Name of the namespace managed by nix-forge/vpn-confinement.";
      };

      bindAddress = mkOption {
        type = types.str;
        readOnly = true;
        default = if cfg.enable then namespace.derived.hostLink.nsAddressIPv4 else "127.0.0.1";
        description = ''
          Service address on the namespace side of the host link. Derived by
          vpn-confinement when enabled; loopback when disabled. This link permits
          host access to declared TCP ports without opening the host firewall.
        '';
      };

      hostIngressPorts.tcp = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "TCP ports published to the host. Enabled homelab services add their Web UI ports.";
      };
    };

    interface = {
      name = mkOption {
        type = types.str;
        default = "wg0";
        description = "WireGuard interface name. Must be unique on the host.";
      };

      privateKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/run/secrets/wireguard-private-key";
        description = "Absolute string path to a root-readable private key outside the Nix store.";
      };

      addressIPv4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "10.64.0.2";
        description = "Provider-assigned tunnel IPv4 address, without a prefix length.";
      };

      addressIPv6 = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "fd00::2";
        description = "Provider-assigned tunnel IPv6 address, without a prefix length. Null disables namespace IPv6.";
      };

      dns = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "10.64.0.1" ];
        description = "Literal resolver IPs reachable through the tunnel. DNS containment uses strict mode.";
      };

      mtu = mkOption {
        type = types.ints.between 1280 65535;
        default = 1420;
        description = "WireGuard MTU. Change only to match the provider or measured path MTU.";
      };
    };

    peer = {
      publicKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "VPN peer's WireGuard public key.";
      };

      endpointHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Literal public IPv4 or IPv6 peer address. Hostnames are rejected to avoid host-side DNS.";
      };

      endpointPort = mkOption {
        type = types.port;
        default = 51820;
        description = "VPN peer's WireGuard UDP port.";
      };

      persistentKeepalive = mkOption {
        type = types.ints.between 0 65535;
        default = 25;
        description = "WireGuard keepalive interval in seconds. Zero disables keepalives.";
      };

      presharedKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional absolute string path to a preshared key outside the Nix store.";
      };
    };

    inboundPorts = {
      tcp = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "TCP ports accepted from the tunnel. The VPN provider must forward these ports separately.";
      };

      udp = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "UDP ports accepted from the tunnel. The VPN provider must forward these ports separately.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = useIPv4 || useIPv6;
        message = "Set homelab.vpn.interface.addressIPv4 or addressIPv6 to a provider-assigned tunnel address.";
      }
      {
        assertion = cfg.peer.publicKey != null;
        message = "homelab.vpn.peer.publicKey must be set.";
      }
      {
        assertion = cfg.peer.endpointHost != null;
        message = "homelab.vpn.peer.endpointHost must be set.";
      }
      {
        assertion = cfg.interface.privateKeyFile != null && hasPrefix "/" cfg.interface.privateKeyFile;
        message = "homelab.vpn.interface.privateKeyFile must be an absolute string path to a runtime secret.";
      }
      {
        assertion = cfg.peer.presharedKeyFile == null || hasPrefix "/" cfg.peer.presharedKeyFile;
        message = "homelab.vpn.peer.presharedKeyFile must be an absolute string path when set.";
      }
      {
        assertion = useIPv4 || builtins.all (hasInfix ":") cfg.interface.dns;
        message = "An IPv6-only VPN requires IPv6 DNS servers in homelab.vpn.interface.dns.";
      }
    ];

    services.vpnConfinement = {
      enable = true;
      namespaces.${cfg.namespace.name} = {
        enable = true;
        wireguard = {
          interface = cfg.interface.name;
          endpointPinning.enable = true;
        };
        dns = {
          mode = "strict";
          servers = cfg.interface.dns;
        };
        ipv6.mode = if useIPv6 then "tunnel" else "disable";
        # Torrent peers are discovered dynamically, so a fixed egress allowlist
        # is unsuitable. The namespace firewall still permits only tunnel egress.
        egress.mode = "allowAllTunnel";
        hostLink.enable = true;
        publishToHost.tcp = cfg.namespace.hostIngressPorts.tcp;
        ingress.fromTunnel = cfg.inboundPorts;
      };
    };

    networking.wireguard.interfaces.${cfg.interface.name} = {
      inherit (cfg.interface) privateKeyFile mtu;
      ips =
        optionals useIPv4 [ "${cfg.interface.addressIPv4}/32" ]
        ++ optionals useIPv6 [ "${cfg.interface.addressIPv6}/128" ];
      peers = [
        {
          inherit (cfg.peer) publicKey presharedKeyFile persistentKeepalive;
          inherit endpoint;
          allowedIPs = optionals useIPv4 [ "0.0.0.0/0" ] ++ optionals useIPv6 [ "::/0" ];
        }
      ];
    };
  };
}
