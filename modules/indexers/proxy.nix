{
  config,
  lib,

  ...
}:
let
  cfg = config.homelab.indexerProxy;
  vpn = config.homelab.vpn;
in
{
  options.homelab.indexerProxy = {
    enable = lib.mkEnableOption "an authenticated VPN-confined SOCKS5 proxy for selected Prowlarr indexers";
    port = lib.mkOption {
      type = lib.types.port;
      default = 1080;
      description = "SOCKS5 port reachable only over the namespace host link.";
    };
    username = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9._-]+";
      default = "prowlarr";
      description = "SOCKS5 username supplied to explicitly configured Prowlarr proxies.";
    };
    usernameFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9_./-]+");
      default = null;
      description = "Runtime file containing the SOCKS5 username; overrides username.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9_./-]+");
      default = null;
      description = "Absolute runtime file containing the SOCKS5 password.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = vpn.enable;
        message = "The indexer proxy requires homelab.vpn.enable.";
      }
      {
        assertion =
          cfg.passwordFile != null
          && !(lib.hasPrefix "/nix/store" cfg.passwordFile)
          && !(lib.hasInfix ":" cfg.passwordFile);
        message = "The indexer proxy requires an absolute runtime passwordFile outside the Nix store.";
      }
      {
        assertion = cfg.usernameFile == null || !(lib.hasPrefix "/nix/store" cfg.usernameFile);
        message = "Indexer proxy usernameFile must remain outside the Nix store.";
      }
      {
        assertion =
          cfg.usernameFile == null || (config.services.microsocks.package.supportsCredentialFiles or false);
        message = "Indexer proxy usernameFile requires a MicroSocks package with native credential-file support.";
      }
    ];
    services.microsocks = {
      enable = true;
      ip = vpn.namespace.bindAddress;
      inherit (cfg) port;
      authUsername = if cfg.usernameFile == null then cfg.username else "runtime-credential";
      authPasswordFile = cfg.passwordFile;
      authOnce = false;
      # Request destinations can contain indexer API keys or passkeys.
      disableLogging = true;
    };
    systemd.services.microsocks.serviceConfig.LoadCredential = lib.mkIf (cfg.usernameFile != null) (
      lib.mkForce [
        "MICROSOCKS_PASSWORD_FILE:${cfg.passwordFile}"
        "MICROSOCKS_USERNAME_FILE:${cfg.usernameFile}"
      ]
    );
    # Native credential-file support is supplied by the host package overlay
    # until upstream accepts private credential files. No credential value
    # enters the Nix store, environment, or process command line.
    systemd.services.microsocks.script = lib.mkIf (cfg.usernameFile != null) (
      lib.mkForce (
        (import ../../lib/render-text.nix) ./scripts/start-authenticated-proxy.sh {
          lib_optionalString_config_services_microsocks_execWrapper_nu = lib.optionalString (
            config.services.microsocks.execWrapper != null
          ) "${config.services.microsocks.execWrapper} ";
          config_services_microsocks_package = config.services.microsocks.package;
          lib_escapeShellArg_vpn_namespace_bindAddress = lib.escapeShellArg vpn.namespace.bindAddress;
          toString_cfg_port = toString cfg.port;
        }
      )
    );
    systemd.services.microsocks.vpn = {
      enable = true;
      namespace = vpn.namespace.name;
      hardeningProfile = "strict";
    };
    homelab.vpn.namespace.hostIngressPorts.tcp = [ cfg.port ];
  };
}
