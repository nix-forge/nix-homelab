{ config, lib, ... }:
let
  cfg = config.homelab.operations.access;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;
  hostname = types.strMatching "[a-z0-9][a-z0-9.-]+";
  runtimePath = types.nullOr (types.strMatching "/[A-Za-z0-9_./-]+");
  backendNames = builtins.attrNames cfg.backends;
  stateDir = "/var/lib/authelia-homelab";
  authOrigin = "https://${cfg.portal}.${cfg.domain}";
  privateFile = path: path != null && !(lib.hasPrefix "/nix/store" path);
  sanitizeHeaders = ''
    request_header -Remote-User
    request_header -Remote-Groups
    request_header -Remote-Name
    request_header -Remote-Email
  '';
in
{
  options.homelab.operations.access = {
    enable = mkEnableOption "private HTTPS access with native Caddy and Authelia";
    domain = mkOption {
      type = hostname;
      default = "homelab.home.arpa";
      description = "Host-owned private DNS/cookie domain; certificates must cover portal and backend hostnames.";
    };
    portal = mkOption {
      type = types.strMatching "[a-z0-9][a-z0-9-]*";
      default = "auth";
      description = "Authentication portal subdomain.";
    };
    bindAddress = mkOption {
      type = types.strMatching "[0-9.]+";
      default = "127.0.0.1";
      description = "Private host IPv4 address for HTTPS. The host owns address assignment and DNS.";
    };
    allowedInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Host interfaces on which to allow HTTPS; empty keeps remote firewall closed.";
    };
    certificateFile = mkOption {
      type = runtimePath;
      default = null;
      description = "User-provided certificate chain with the required DNS names.";
    };
    keyFile = mkOption {
      type = runtimePath;
      default = null;
      description = "User-provided nix-seal TLS private key.";
    };
    usersFile = mkOption {
      type = runtimePath;
      default = null;
      description = "nix-seal Authelia YAML user database with Argon2id password hashes and group membership; updates require service restart.";
    };
    jwtSecretFile = mkOption {
      type = runtimePath;
      default = null;
      description = "nix-seal identity-validation secret.";
    };
    sessionSecretFile = mkOption {
      type = runtimePath;
      default = null;
      description = "nix-seal session secret.";
    };
    storageEncryptionKeyFile = mkOption {
      type = runtimePath;
      default = null;
      description = "nix-seal persistent identity-storage encryption key; retain with recovery material.";
    };
    backends = mkOption {
      default = { };
      description = "Browser-compatible protected services. Native app authentication remains enabled; applications with non-browser clients need separate compatibility validation.";
      type = types.attrsOf (
        types.submodule (
          { name, ... }: {
            options = {
              unit = mkOption {
                type = types.strMatching "[A-Za-z0-9_-]+";
                default =
                  if name == "dashboard" then
                    "homepage-dashboard"
                  else if name == "health" then
                    "gatus"
                  else
                    name;
                description = "Existing backend systemd service name without .service; coupled to the ingress guard for fail-closed shutdown.";
              };
              port = mkOption {
                type = types.port;
                description = "Loopback-only backend HTTP port.";
              };
              policy = mkOption {
                type = types.enum [
                  "one_factor"
                  "two_factor"
                ];
                default = "two_factor";
                description = "Authentication policy; two-factor enrollment is the default.";
              };
              subjects = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Authelia subjects, such as group:media; empty permits any authenticated user meeting the policy.";
              };
            };
          }
        )
      );
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.operations.enable;
        message = "Private access requires homelab.operations.enable for identity recovery inventory.";
      }
      {
        assertion =
          cfg.backends != { }
          && !(builtins.elem cfg.portal backendNames)
          && lib.all (name: builtins.match "[a-z0-9][a-z0-9-]*" name != null) backendNames;
        message = "Private access needs backend names distinct from its authentication portal.";
      }
      {
        assertion = lib.all privateFile [
          cfg.certificateFile
          cfg.keyFile
          cfg.usersFile
          cfg.jwtSecretFile
          cfg.sessionSecretFile
          cfg.storageEncryptionKeyFile
        ];
        message = "Private access requires user-provided runtime certificates, users and secrets outside the Nix store.";
      }
      {
        assertion =
          lib.hasPrefix "127." cfg.bindAddress
          || lib.hasPrefix "10." cfg.bindAddress
          || lib.hasPrefix "192.168." cfg.bindAddress
          || builtins.match "172\\.(1[6-9]|2[0-9]|3[01])\\..+" cfg.bindAddress != null;
        message = "Private access bindAddress must be loopback or an RFC1918 private address.";
      }
      {
        assertion = lib.all (
          backend:
          !(builtins.elem backend.port [
            443
            9091
          ])
        ) (builtins.attrValues cfg.backends);
        message = "Protected backend ports must not collide with HTTPS or Authelia.";
      }
    ];
    homelab.operations.state.authelia = {
      paths = [ stateDir ];
      units = [ "authelia-homelab.service" ];
    };
    services = {
      authelia.instances.homelab = {
        enable = true;
        secrets = { inherit (cfg) jwtSecretFile sessionSecretFile storageEncryptionKeyFile; };
        settings = {
          theme = "auto";
          log.level = "info";
          server.address = "tcp://127.0.0.1:9091/";
          authentication_backend = {
            password_reset.disable = true;
            file = {
              path = "/run/credentials/authelia-homelab.service/users";
              watch = false;
            };
          };
          access_control = {
            default_policy = "deny";
            rules = lib.mapAttrsToList (
              name: backend:
              {
                domain = "${name}.${cfg.domain}";
                inherit (backend) policy;
              }
              // lib.optionalAttrs (backend.subjects != [ ]) { subject = backend.subjects; }
            ) cfg.backends;
          };
          session = {
            name = "homelab_session";
            same_site = "lax";
            inactivity = "5m";
            expiration = "1h";
            remember_me = "0";
            cookies = [
              {
                inherit (cfg) domain;
                authelia_url = authOrigin;
              }
            ];
          };
          storage.local.path = "${stateDir}/db.sqlite3";
          notifier.filesystem.filename = "${stateDir}/notifications.txt";
          totp.issuer = cfg.domain;
          regulation = {
            max_retries = 3;
            find_time = "2m";
            ban_time = "5m";
          };
        };
      };
      caddy = {
        enable = true;
        openFirewall = false;
        # Eliminate the unauthenticated local administration HTTP API. Changes
        # restart Caddy through the native module instead of using API reloads.
        enableReload = false;
        globalConfig = ''
          admin off
          auto_https disable_redirects
          default_bind ${cfg.bindAddress}
        '';
        virtualHosts = lib.listToAttrs (
          [
            (lib.nameValuePair "${cfg.portal}.${cfg.domain}" {
              extraConfig = ''
                tls /run/credentials/caddy.service/access-cert /run/credentials/caddy.service/access-key
                ${sanitizeHeaders}
                reverse_proxy 127.0.0.1:9091
              '';
            })
          ]
          ++ lib.mapAttrsToList (
            name: backend:
            lib.nameValuePair "${name}.${cfg.domain}" {
              extraConfig = ''
                tls /run/credentials/caddy.service/access-cert /run/credentials/caddy.service/access-key
                route {
                  ${sanitizeHeaders}
                  forward_auth 127.0.0.1:9091 {
                    uri /api/authz/forward-auth
                    copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
                  }
                  reverse_proxy 127.0.0.1:${toString backend.port}
                }
              '';
            }
          ) cfg.backends
        );
      };
      homepage-dashboard.allowedHosts = mkIf (builtins.elem "dashboard" backendNames) "dashboard.${cfg.domain}";
    };
    systemd.services = lib.mkMerge [
      (lib.genAttrs
        (lib.unique (
          [
            "caddy"
            "authelia-homelab"
          ]
          ++ map (backend: backend.unit) (builtins.attrValues cfg.backends)
        ))
        (_: {
          after = [ "nftables.service" ];
          requires = [ "nftables.service" ];
          bindsTo = [ "nftables.service" ];
          partOf = [ "nftables.service" ];
        })
      )
      {
        authelia-homelab.serviceConfig.LoadCredential = [ "users:${cfg.usersFile}" ];
        caddy.serviceConfig.LoadCredential = [
          "access-cert:${cfg.certificateFile}"
          "access-key:${cfg.keyFile}"
        ];
      }
    ];
    networking.firewall.interfaces = lib.genAttrs cfg.allowedInterfaces (_: {
      allowedTCPPorts = [ 443 ];
    });
    # Defense against an accidentally widened backend listener. Native services
    # still need loopback binds; a local authenticated application API is allowed.
    networking.nftables = {
      enable = true;
      tables.homelab-private-backends = {
        family = "inet";
        content = ''
          chain protect {
            type filter hook input priority -5; policy accept;
            iifname != "lo" tcp dport { ${
              lib.concatStringsSep ", " (
                map toString (
                  lib.unique ([ 9091 ] ++ map (backend: backend.port) (builtins.attrValues cfg.backends))
                )
              )
            } } drop
          }
        '';
      };
    };

  };
}
