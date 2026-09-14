{ lib, config, ... }:
let
  inherit (lib)
    hasInfix
    hasPrefix
    hasSuffix
    mkEnableOption
    mkIf
    mkOption
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
  safeRuntimePath =
    path:
    path == null
    || (
      hasPrefix "/" path
      && !(hasPrefix "/nix/store" path)
      && !(hasInfix "/../" "${path}/")
      && !(hasInfix "/./" "${path}/")
      && !(hasInfix "//" path)
      && !(hasInfix ":" path)
      && !(hasInfix "\n" path)
      && !(hasInfix "\r" path)
    );

in
{
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
        assertion = safeRuntimePath cfg.interface.privateKeyFile && cfg.interface.privateKeyFile != null;
        message = "homelab.vpn.interface.privateKeyFile must be an absolute runtime path outside the Nix store.";
      }
      {
        assertion = safeRuntimePath cfg.peer.presharedKeyFile;
        message = "homelab.vpn.peer.presharedKeyFile must be an absolute runtime path outside the Nix store.";
      }
      {
        assertion = builtins.match "[0-9A-Fa-f:.]+" endpointHost != null;
        message = "homelab.vpn.peer.endpointHost must be a literal IPv4 or IPv6 address.";
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
        # Validate every attached service without restricting dynamic VPN peers.
        servicePolicy = "enforced";
        wireguard = {
          interface = cfg.interface.name;
          endpointPinning.enable = true;
        };
        dns = {
          mode = "strict";
          servers = cfg.interface.dns;
        };
        ipv6.mode = if useIPv6 then "tunnel" else "disable";
        # Inherit egress from the namespace profile: balanced supports dynamic
        # tunnel peers; highAssurance retains its destination allowlist.
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
