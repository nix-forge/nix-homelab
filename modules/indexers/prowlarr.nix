{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.apps.prowlarr;
  vpn = config.homelab.vpn;
in
{
  options.homelab.apps.prowlarr = {
    customDefinitions = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Immutable public Cardigann YAML definitions, keyed by filename. Declared files replace that name; unmanaged files remain untouched. Remove retired definitions explicitly.";
    };
    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = if cfg.vpn.enable then vpn.namespace.bindAddress else "127.0.0.1";
      description = "Prowlarr listen address.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 9696;
      description = "Default Prowlarr TCP port; native services.prowlarr.settings.server.port can override it.";
    };
    vpn.enable = lib.mkEnableOption "confinement of all Prowlarr traffic, including app sync";
    proxyOnly = lib.mkEnableOption "blocking direct public egress while selected indexers use the VPN SOCKS proxy";
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [

        {
          assertion = cfg.vpn.enable -> vpn.enable;
          message = "Prowlarr VPN requires homelab.vpn.enable.";
        }
        {
          assertion =
            !cfg.proxyOnly
            || (
              vpn.enable
              && !cfg.vpn.enable
              && config.services.prowlarr.settings.server.bindaddress == "127.0.0.1"
              && config.homelab.indexerProxy.enable
            );
          message = "Proxy-only Prowlarr requires a loopback listener and a VPN-confined indexer proxy.";
        }
        {
          assertion =
            !cfg.proxyOnly
            || (
              config.systemd.services.prowlarr.serviceConfig.IPAddressDeny == [ "any" ]
              &&
                config.systemd.services.prowlarr.serviceConfig.IPAddressAllow == [
                  "127.0.0.0/8"
                  "::1/128"
                  "${vpn.namespace.bindAddress}/32"
                ]
            );
          message = "Proxy-only Prowlarr must deny every public IP destination.";
        }
      ];
      services.prowlarr.settings = {
        server = {
          bindaddress = lib.mkDefault cfg.bindAddress;
          port = lib.mkDefault cfg.port;
        };
      };
      systemd.services.prowlarr.vpn = {
        inherit (cfg.vpn) enable;
        namespace = vpn.namespace.name;
      };
      homelab.networkPolicy.localOnlyServices = lib.mkIf cfg.proxyOnly [ "prowlarr" ];
      homelab.vpn.namespace.hostIngressPorts.tcp = lib.mkIf cfg.vpn.enable [
        config.services.prowlarr.settings.server.port
      ];
      warnings = lib.optional cfg.vpn.enable "Confined Prowlarr cannot initiate host/LAN app-sync connections. Use an indexer proxy for selective privacy or keep target apps in the same namespace.";
    })
    (lib.mkIf (cfg.customDefinitions != { }) {
      assertions = [
        {
          assertion = lib.all (
            source: builtins.isPath source || lib.hasPrefix "${builtins.storeDir}/" (toString source)
          ) (lib.attrValues cfg.customDefinitions);
          message = "Custom Prowlarr definitions must use public Nix sources, not mutable runtime files.";
        }
        {
          assertion = config.services.prowlarr.enable;
          message = "Custom Prowlarr definitions require services.prowlarr.enable.";
        }
        {
          assertion = lib.all (name: builtins.match "[A-Za-z0-9][A-Za-z0-9_.-]*[.](yml|yaml)" name != null) (
            lib.attrNames cfg.customDefinitions
          );
          message = "Custom Prowlarr definitions require safe YAML filenames.";
        }
      ];
      systemd.services.prowlarr.serviceConfig.ExecStartPre =
        let
          installer = pkgs.writers.writePython3Bin "install-prowlarr-definitions" {
            flakeIgnore = [
              "E501"
              "W503"
            ];
          } ../../scripts/indexers/install_definitions.py;
          specification =
            (pkgs.formats.json { }).generate "prowlarr-custom-definitions.json"
              cfg.customDefinitions;
          # Native Prowlarr binds custom dataDir at this fixed application path.
          # DynamicUser exposes the state beneath its private directory namespace.
          dynamic = config.systemd.services.prowlarr.serviceConfig.DynamicUser or false;
          state = if dynamic then "/var/lib/private/prowlarr" else "/var/lib/prowlarr";
        in
        [
          # Retain the filesystem sandbox while updating existing root-owned files.
          (
            "!"
            + (import ../../lib/systemd-args.nix) [
              (lib.getExe installer)
              state
              specification
              builtins.storeDir
            ]
          )
        ];
    })
  ];
}
