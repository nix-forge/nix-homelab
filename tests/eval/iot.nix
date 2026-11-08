{
  evaluate,
  lib,
  pkgs,
}:
let
  base = {
    services = {
      avahi.enable = true;
      homebridge = {
        enable = true;
        openFirewall = false;
        settings.bridge = {
          port = 51826;
          bind = [ "eth0" ];
          advertiser = "avahi";
        };
        settings.ports = {
          start = 51827;
          end = 51828;
        };
        managedUi = {
          enable = true;
          uiUsernameFile = "/run/credentials/homebridge-user";
          uiPasswordFile = "/run/credentials/homebridge-password";
        };
      };
      scrypted = {
        enable = true;
        package = pkgs.writeShellScriptBin "scrypted-serve" "exit 0";
        nodePackage = pkgs.nodejs;
        listenAddress = "192.168.1.20";
        uiUsernameFile = "/run/credentials/scrypted-user";
        uiPasswordFile = "/run/credentials/scrypted-password";
        plugins = [
          {
            name = "@scrypted/snapshot";
            version = "0.2.68";
            source = "npm";
          }
        ];
      };
    };
  };
  configured = (evaluate base).config;
  empty = (evaluate { }).config;
  invalid =
    (evaluate (
      lib.recursiveUpdate base {
        services.homebridge.managedUi.uiPasswordFile = "/nix/store/exposed-password";
        services.scrypted.plugins = [
          {
            name = "@scrypted/snapshot";
            version = "0.2.68";
            source = "npm";
          }
          {
            name = "@scrypted/snapshot";
            version = "0.2.69";
            source = "npm";
          }
        ];
      }
    )).config;
in
{
  iotIsOptIn =
    !empty.services.homebridge.enable && !builtins.hasAttr "scrypted" empty.systemd.services;
  homebridgePrivateUi =
    configured.services.homebridge.uiSettings.host == "127.0.0.1"
    && !configured.services.homebridge.openFirewall;
  homebridgeOwnsStateAndCredentials =
    configured.systemd.services.homebridge.serviceConfig.StateDirectoryMode == "0700"
    && builtins.elem "ui-password:/run/credentials/homebridge-password" configured.systemd.services.homebridge.serviceConfig.LoadCredential;
  scryptedOwnsStateAndCredentials =
    configured.systemd.services.scrypted.serviceConfig.User == "scrypted"
    && configured.systemd.services.scrypted.serviceConfig.StateDirectory == "scrypted"
    && builtins.elem "ui-password:/run/credentials/scrypted-password" configured.systemd.services.scrypted.serviceConfig.LoadCredential;
  scryptedProvidesNativePluginLibraries =
    (configured.systemd.services.scrypted.environment.LD_LIBRARY_PATH or "")
    == lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
  scryptedPluginIsOptIn = builtins.hasAttr "scrypted-plugins" configured.systemd.services;
  validAssertionsPass = lib.all (item: item.assertion) configured.assertions;
  invalidCredentialsAndPluginsFail =
    lib.length (lib.filter (item: !item.assertion) invalid.assertions) >= 2;
}
