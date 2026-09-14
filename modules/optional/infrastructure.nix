{ config, lib, ... }:
let
  enabled = name: config.homelab.optional.apps.${name}.enable;
in
{
  config = lib.mkMerge [
    (lib.mkIf (enabled "adguardhome") {
      services.adguardhome = {
        host = lib.mkDefault "127.0.0.1";
        openFirewall = lib.mkDefault false;
        allowDHCP = lib.mkDefault false;
        settings.dns = {
          bind_hosts = lib.mkDefault [ "127.0.0.1" ];
          port = lib.mkDefault 5353;
        };
      };
    })
    (lib.mkIf (enabled "scrutiny") {
      services.scrutiny = {
        openFirewall = lib.mkDefault false;
        settings.web = {
          listen = {
            host = lib.mkDefault "127.0.0.1";
            port = lib.mkDefault 8083;
          };
          influxdb.host = lib.mkDefault "127.0.0.1";
        };
        collector = {
          enable = lib.mkDefault false;
          schedule = lib.mkDefault "daily";
        };
      };
      services.influxdb2.settings.http-bind-address = lib.mkIf config.services.scrutiny.influxdb.enable (
        lib.mkDefault "127.0.0.1:8086"
      );
    })
  ];
}
