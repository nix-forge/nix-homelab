{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.reactflux;
  minifluxAddress = config.services.miniflux.config.LISTEN_ADDR;
  headers = ''
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Content-Security-Policy "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data: https:; connect-src 'self'; media-src 'self' https: blob:; frame-src https://www.youtube-nocookie.com https://www.youtube.com https://player.vimeo.com; worker-src 'self' blob:; manifest-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'; upgrade-insecure-requests" always;
  '';
in
{
  options.homelab.optional.reactflux = {
    enable = lib.mkEnableOption "the modern static ReactFlux reader over Miniflux";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.reactflux;
      description = "Static ReactFlux package, including optional deployment defaults.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 18082;
      description = "Loopback-only frontend listener, for a separate HTTPS proxy.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.miniflux.enable && lib.hasPrefix "127.0.0.1:" minifluxAddress;
        message = "ReactFlux requires the private local Miniflux backend.";
      }
    ];
    services.nginx = {
      enable = true;
      virtualHosts.homelab-news-internal = {
        listen = [
          {
            addr = "127.0.0.1";
            inherit (cfg) port;
          }
        ];
        root = "${cfg.package}/share/reactflux";
        extraConfig = ''
          access_log off;
          ${headers}
        '';
        locations = {
          "/".tryFiles = "$uri $uri/ /index.html";
          "/assets/".extraConfig = ''
            try_files $uri =404;
            ${headers}
            add_header Cache-Control "public, max-age=31536000, immutable";
          '';
          "= /index.html".extraConfig = ''
            ${headers}
            add_header Cache-Control "no-cache";
          '';
          "= /sw.js".extraConfig = ''
            ${headers}
            add_header Cache-Control "no-cache";
          '';
          # Credentials travel only to this fixed local backend. The proxy does
          # not store them, open an arbitrary URL, or cache authenticated data.
          "/v1/" = {
            proxyPass = "http://${minifluxAddress}";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_buffering off;
              ${headers}
              add_header Cache-Control "no-store" always;
            '';
          };
          "/proxy/" = {
            proxyPass = "http://${minifluxAddress}";
            extraConfig = "proxy_set_header X-Forwarded-Proto https;";
          };
          "/feed-icon/" = {
            proxyPass = "http://${minifluxAddress}";
            extraConfig = "proxy_set_header X-Forwarded-Proto https;";
          };
        };
      };
    };
  };
}
