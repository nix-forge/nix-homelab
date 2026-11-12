{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.networkPolicy;
  allowed = [
    "127.0.0.0/8"
    "::1/128"
    "${config.homelab.vpn.namespace.bindAddress}/32"
  ];
  noHostDnsResolv = pkgs.writeText "homelab-no-host-dns-resolv.conf" "nameserver 127.0.0.2\n";
  noHostDnsNsswitch = pkgs.writeText "homelab-no-host-dns-nsswitch.conf" "hosts: files dns\n";
  addressFamilies = lib.mkAfter [
    "AF_INET"
    "AF_INET6"
    "AF_UNIX"
    # Servarr observes local network changes through a netlink socket when
    # validating downloader proxy bypass rules.
    "AF_NETLINK"
  ];
  direct = {
    IPAddressDeny = [
      "0.0.0.0/8"
      "10.0.0.0/8"
      "100.64.0.0/10"
      "172.16.0.0/12"
      "192.168.0.0/16"
      "169.254.0.0/16"
      "198.18.0.0/15"
      "224.0.0.0/4"
      "240.0.0.0/4"
      "fc00::/7"
      "fe80::/10"
      "ff00::/8"
    ];
    IPAddressAllow = allowed;
    RestrictAddressFamilies = addressFamilies;
  };
  localOnly = {
    IPAddressDeny = [ "any" ];
    IPAddressAllow = allowed;
    RestrictAddressFamilies = addressFamilies;
    BindReadOnlyPaths = [
      "${noHostDnsResolv}:/etc/resolv.conf"
      "${noHostDnsNsswitch}:/etc/nsswitch.conf"
    ];
    InaccessiblePaths = [
      "-/run/systemd/resolve/io.systemd.Resolve"
      "-/run/systemd/resolve/io.systemd.Resolve.Monitor"
      "-/run/nscd"
      "-/run/dbus/system_bus_socket"
      "-/var/run/dbus/system_bus_socket"
    ];
  };
  effective = name: config.systemd.services.${name}.serviceConfig;
  sameAllowed =
    service: policy:
    lib.sort builtins.lessThan service.IPAddressAllow
    == lib.sort builtins.lessThan policy.IPAddressAllow;
in
{
  options.homelab.networkPolicy = {
    directServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Selected public-metadata services that may use direct Internet access but cannot reach private networks.";
    };
    localOnlyServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Selected services limited to loopback and the homelab host link, without host DNS access.";
    };
  };

  config = lib.mkIf (cfg.directServices != [ ] || cfg.localOnlyServices != [ ]) {
    assertions = [
      {
        assertion =
          lib.all (name: builtins.match "[A-Za-z0-9@_.-]+" name != null) (
            cfg.directServices ++ cfg.localOnlyServices
          )
          &&
            builtins.length (cfg.directServices ++ cfg.localOnlyServices)
            == builtins.length (lib.unique (cfg.directServices ++ cfg.localOnlyServices));
        message = "Network policy service names must be safe and each service must have exactly one egress policy.";
      }
    ]
    ++ map (name: {
      assertion =
        (effective name).IPAddressDeny == direct.IPAddressDeny && sameAllowed (effective name) direct;
      message = "${name} must deny private networks while allowing public metadata and the selected local link.";
    }) cfg.directServices
    ++ map (name: {
      assertion =
        (effective name).IPAddressDeny == localOnly.IPAddressDeny
        && sameAllowed (effective name) localOnly
        && lib.all (path: builtins.elem path (effective name).BindReadOnlyPaths) localOnly.BindReadOnlyPaths
        && lib.all (
          path: builtins.elem path (effective name).InaccessiblePaths
        ) localOnly.InaccessiblePaths;
      message = "${name} must block direct Internet and host DNS access; only local API links are allowed.";
    }) cfg.localOnlyServices;

    systemd.services =
      lib.genAttrs cfg.directServices (_: {
        serviceConfig = direct;
      })
      // lib.genAttrs cfg.localOnlyServices (_: {
        serviceConfig = localOnly;
      });
  };
}
