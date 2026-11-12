{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.homebridge;
  plugins = cfg.declarativePlugins;
  pluginName = package: package.homebridgePluginName or (lib.getName package);
  names = map pluginName plugins;
  manifest = pkgs.writeText "homebridge-managed-plugins.json" (
    builtins.toJSON (
      map (package: {
        name = pluginName package;
        source = "${package}/lib/node_modules/${pluginName package}";
      }) plugins
    )
  );
in
{
  options.services.homebridge.declarativePlugins = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    example = lib.literalExpression "[ pkgs.homebridge-samsung-tizen ]";
    description = ''
      Homebridge plugin packages installed in the standard lib/node_modules
      directory. A scoped package can set passthru.homebridgePluginName to its
      npm name. Nix reconciles only links it owns; UI-managed plugins and pairing
      state remain writable. Update these packages through Nix rather than the
      Homebridge UI.
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (
          name: builtins.match "(@[a-z0-9-]+/)?homebridge-[a-z0-9-]+" name != null
        ) names;
        message = "Homebridge declarative plugin names must be homebridge-* npm packages, optionally scoped.";
      }
      {
        assertion = lib.length names == lib.length (lib.unique names);
        message = "Homebridge declarative plugin package names must be unique.";
      }
    ];

    systemd.services.homebridge.preStart = lib.mkAfter (
      (import ../../lib/render-text.nix) ./scripts/homebridge-install-plugins.sh {
        lib_getExe_pkgs_util_linux_runuser = lib.getExe' pkgs.util-linux "runuser";
        lib_escapeShellArg_cfg_user = lib.escapeShellArg cfg.user;
        lib_escapeShellArg_cfg_group = lib.escapeShellArg cfg.group;
        lib_getExe_pkgs_python3 = lib.getExe pkgs.python3;
        scripts_homebridge_plugins_py = ./scripts/homebridge_plugins.py;
        inherit manifest;
        lib_escapeShellArg_cfg_pluginPath = lib.escapeShellArg cfg.pluginPath;
      }
    );
  };
}
