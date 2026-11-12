{ config, lib, ... }:
let
  cfg = config.homelab.operations.lanHttps;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  siteNames = builtins.attrNames cfg.sites;
  siteHost = name: "${name}.${cfg.domain}";
  certificate = config.security.acme.certs.${cfg.certificateHost};
  certificateNames = [ (certificate.domain or cfg.certificateHost) ] ++ certificate.extraDomainNames;
  coversSite =
    name:
    builtins.elem (siteHost name) certificateNames || builtins.elem "*.${cfg.domain}" certificateNames;
  decimal =
    value:
    builtins.foldl' (number: digit: number * 10 + lib.toInt digit) 0 (lib.stringToCharacters value);
  ipv4Octets =
    address:
    if builtins.match "[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}" address == null then
      null
    else
      map decimal (lib.splitString "." address);
  literalIPv4 =
    address:
    let
      octets = ipv4Octets address;
    in
    octets != null
    && lib.all (octet: octet <= 255) octets
    && lib.concatMapStringsSep "." toString octets == address;
  literalIPv6 =
    address:
    let
      halves = lib.splitString "::" address;
      groups = value: if value == "" then [ ] else lib.splitString ":" value;
      validGroups = values: lib.all (value: builtins.match "[0-9A-Fa-f]{1,4}" value != null) values;
      expanded = lib.splitString ":" address;
      compressed = lib.concatMap groups halves;
    in
    if lib.length halves == 1 then
      lib.length expanded == 8 && validGroups expanded
    else
      lib.length halves == 2 && lib.length compressed < 8 && validGroups compressed;
  literalAddress = address: literalIPv4 address || literalIPv6 address;
  unspecifiedIPv6 =
    address:
    lib.hasInfix ":" address
    && lib.all (segment: segment == "" || builtins.match "0+" segment != null) (
      lib.splitString ":" address
    );
  literalCIDR =
    cidr:
    let
      parts = builtins.match "([0-9A-Fa-f:.]+)/([0-9]{1,3})" cidr;
      address = if parts == null then "" else builtins.elemAt parts 0;
      prefix = if parts == null then 0 else decimal (builtins.elemAt parts 1);
    in
    parts != null
    && literalAddress address
    && prefix > 0
    && prefix <= (if lib.hasInfix ":" address then 128 else 32);
  # Backends use literal addresses so DNS cannot redirect a trusted name.
  # IPv6 backends and self-signed HTTPS backends stay on loopback.
  privateUpstream =
    url:
    let
      loopback = builtins.match "(http|https)://[[]::1[]]:([0-9]{1,5})" url;
      loopbackPort = if loopback == null then 0 else decimal (builtins.elemAt loopback 1);
      tls = lib.hasPrefix "https://" url;
      parts = builtins.match "${if tls then "https" else "http"}://([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}):([0-9]{1,5})" url;
      address = if parts == null then "" else builtins.elemAt parts 0;
      octets = ipv4Octets address;
      port = if parts == null then 0 else decimal (builtins.elemAt parts 1);
    in
    (loopback != null && loopbackPort > 0 && loopbackPort <= 65535)
    || (
      parts != null
      && literalIPv4 address
      && port > 0
      && port <= 65535
      && (!tls || address == "127.0.0.1")
      && (
        builtins.elem (builtins.head octets) [
          10
          127
        ]
        || (builtins.elemAt octets 0 == 192 && builtins.elemAt octets 1 == 168)
        || (builtins.elemAt octets 0 == 169 && builtins.elemAt octets 1 == 254)
        || (builtins.elemAt octets 0 == 172 && lib.elem (builtins.elemAt octets 1) (lib.range 16 31))
      )
    );

in
{
  options.homelab.operations.lanHttps = {
    enable = mkEnableOption "LAN-only HTTPS for applications with their own authentication";
    domain = mkOption {
      type = types.strMatching "[a-z0-9][a-z0-9.-]+";
      description = "Host-owned DNS domain for the declared application names.";
    };
    certificateHost = mkOption {
      type = types.strMatching "[a-z0-9][a-z0-9.-]+";
      description = "Host-owned ACME certificate whose names cover every enabled site.";
    };
    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" ];
      description = "Literal IP addresses for HTTPS listeners. The host must also restrict its firewall.";
    };
    allowedCIDRs = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.0/8" ];
      description = "Literal client CIDRs permitted at nginx, independent of host firewall policy.";
    };
    sites = mkOption {
      default = { };
      description = "Named HTTPS sites. Each backend retains its own authentication and loopback or private listener.";
      type = types.attrsOf (
        types.submodule {
          options = {
            upstream = mkOption {
              type = types.str;
              description = "Literal private IPv4 HTTP upstream, or IPv4/IPv6 loopback HTTP(S) upstream; no URI path.";
            };
            streaming = mkOption {
              type = types.bool;
              default = false;
              description = "Disable response buffering and permit long media streams.";
            };
            upstreamHostHeader = mkOption {
              type = types.bool;
              default = false;
              description = "Send the upstream host as Host for backends that validate their local listener, while preserving the public name in X-Forwarded-Host.";
            };
            allowedCIDRs = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = "Site-specific client CIDRs, or null to inherit the LAN HTTPS policy.";
            };
          };
        }
      );
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.attrByPath [ "homelab" "operations" "access" "enable" ] false config);
        message = "LAN HTTPS and Authelia access cannot own port 443 on the same host.";
      }
      {
        assertion =
          siteNames != [ ]
          && lib.all (name: builtins.match "[a-z0-9][a-z0-9-]*" name != null) siteNames
          && cfg.listenAddresses != [ ]
          && cfg.allowedCIDRs != [ ];
        message = "LAN HTTPS requires named sites, explicit listeners and permitted client networks.";
      }
      {
        assertion =
          builtins.hasAttr cfg.certificateHost config.security.acme.certs && lib.all coversSite siteNames;
        message = "The selected ACME certificate must cover every LAN HTTPS site name.";
      }
      {
        assertion = lib.all (site: privateUpstream site.upstream) (builtins.attrValues cfg.sites);
        message = "LAN HTTPS upstreams must be literal private IPv4 HTTP or IPv4/IPv6 loopback HTTP(S) endpoints with valid ports.";
      }
      {
        assertion =
          lib.all (
            address:
            literalAddress address
            && !builtins.elem address [
              "0.0.0.0"
              "::"
            ]
            && !unspecifiedIPv6 address
          ) cfg.listenAddresses
          &&
            lib.all
              (
                cidr:
                literalCIDR cidr
                && !builtins.elem cidr [
                  "0.0.0.0/0"
                  "::/0"
                ]
              )
              (
                cfg.allowedCIDRs
                ++ lib.concatMap (site: if site.allowedCIDRs == null then [ ] else site.allowedCIDRs) (
                  builtins.attrValues cfg.sites
                )
              );
        message = "LAN HTTPS requires literal listener IPs and restricted literal client CIDRs.";
      }
    ];
    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      virtualHosts = {
        _homelab-reject-unknown = {
          default = true;
          rejectSSL = true;
          listen = map (addr: {
            inherit addr;
            port = 443;
            ssl = true;
          }) cfg.listenAddresses;
        };
      }
      // lib.mapAttrs' (
        name: site:
        lib.nameValuePair (siteHost name) {
          onlySSL = true;
          useACMEHost = cfg.certificateHost;
          inherit (cfg) listenAddresses;
          extraConfig = ''
            ${lib.concatMapStringsSep "\n" (cidr: "allow ${cidr};") (
              if site.allowedCIDRs == null then cfg.allowedCIDRs else site.allowedCIDRs
            )}
            deny all;
            access_log off;
            client_max_body_size 20m;
            add_header X-Content-Type-Options nosniff always;
            add_header Strict-Transport-Security "max-age=31536000" always;
          '';
          locations."/" = {
            proxyPass = site.upstream;
            proxyWebsockets = true;
            extraConfig = ''
              proxy_cookie_flags ~.* secure;
              proxy_set_header Host ${if site.upstreamHostHeader then "$proxy_host" else "$host"};
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Host $host;
              ${lib.optionalString (lib.hasPrefix "https://" site.upstream) "proxy_ssl_verify off;"}
              ${lib.optionalString site.streaming ''
                proxy_buffering off;
                proxy_read_timeout 3600s;
              ''}
            '';
          };
        }
      ) cfg.sites;
    };
  };
}
