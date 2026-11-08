{ evaluate, lib }:
let
  configured =
    (evaluate {
      imports = [ ../../examples/media-server.nix ];
      homelab.apps.slskd = {
        enable = true;
        credentialsFile = "/run/secrets/slskd.env";
      };
    }).config;
  rejected = extra: lib.any (assertion: !assertion.assertion) (evaluate extra).config.assertions;
  unit = configured.systemd.services.slskd;
  namespace = configured.services.vpnConfinement.namespaces.${configured.homelab.vpn.namespace.name};
in
{
  disabledByDefault = !(evaluate { }).config.services.slskd.enable;
  privateCredentials =
    configured.services.slskd.environmentFile == "/run/secrets/slskd.env"
    && unit.serviceConfig.EnvironmentFile == "/run/secrets/slskd.env";
  noPublicWebListener =
    configured.services.slskd.settings.web.ip_address == configured.homelab.vpn.namespace.bindAddress
    && !configured.services.slskd.openFirewall
    && configured.networking.firewall.allowedTCPPorts == [ ];
  vpnAttachment =
    unit.vpn.enable
    && unit.vpn.namespace == configured.homelab.vpn.namespace.name
    && unit.serviceConfig.NetworkNamespacePath == "/run/netns/${configured.homelab.vpn.namespace.name}";
  tunnelDnsAndEndpoint =
    namespace.servicePolicy == "enforced"
    && namespace.dns.mode == "strict"
    && !namespace.dns.allowHostResolverIPC
    && namespace.wireguard.endpointPinning.enable;
  onlyWebPortOnHostLink =
    builtins.elem 5030 namespace.publishToHost.tcp
    && !(builtins.elem 50300 namespace.publishToHost.tcp);
  noUnforwardedPeerPort = namespace.ingress.fromTunnel.tcp == [ ];
  privateDownloads =
    configured.services.slskd.settings.directories.downloads == "/var/lib/slskd/downloads"
    && configured.services.slskd.settings.directories.incomplete == "/var/lib/slskd/incomplete"
    && unit.serviceConfig.UMask == "0007";
  sharedDownloadFilesystem =
    let
      shared =
        (evaluate {
          imports = [ ../../examples/media-server.nix ];
          homelab.apps.slskd = {
            enable = true;
            credentialsFile = "/run/secrets/slskd.env";
            downloadsDir = "/data/downloads/soulseek/complete";
            incompleteDir = "/data/downloads/soulseek/incomplete";
            downloadGroup = "media";
            downloadDirectoryMode = "2770";
          };
        }).config;
    in
    shared.services.slskd.settings.directories.downloads == "/data/downloads/soulseek/complete"
    && builtins.elem "/data/downloads/soulseek/complete" shared.systemd.services.slskd.serviceConfig.ReadWritePaths
    && builtins.elem "/data/downloads/soulseek/incomplete" shared.systemd.services.slskd.unitConfig.RequiresMountsFor
    && builtins.elem "homelab-slskd-directories.service" shared.systemd.services.slskd.requires
    && !lib.any (rule: lib.hasInfix "/data/downloads/soulseek" rule) shared.systemd.tmpfiles.rules;
  collidingDownloadPathsRejected = rejected {
    imports = [ ../../examples/media-server.nix ];
    homelab.apps.slskd = {
      enable = true;
      credentialsFile = "/run/secrets/slskd.env";
      downloadsDir = "/data/same";
      incompleteDir = "/data/same";
    };
  };
  credentialPreflight = builtins.length unit.serviceConfig.ExecStartPre == 1;
  renderedUnit = builtins.stringLength configured.systemd.units."slskd.service".text > 0;
  missingCredentialsRejected = rejected { homelab.apps.slskd.enable = true; };
  storeCredentialsRejected = rejected {
    imports = [ ../../examples/media-server.nix ];
    homelab.apps.slskd = {
      enable = true;
      credentialsFile = "/nix/store/public.env";
    };
  };
  absentVpnRejected = rejected {
    homelab.apps.slskd = {
      enable = true;
      credentialsFile = "/run/secrets/slskd.env";
    };
  };
  directRequiresExplicitOptOut = rejected {
    homelab.apps.slskd = {
      enable = true;
      credentialsFile = "/run/secrets/slskd.env";
      vpn.enable = false;
    };
  };
  explicitDirectStaysLocal =
    let
      direct =
        (evaluate {
          homelab.apps.slskd = {
            enable = true;
            credentialsFile = "/run/secrets/slskd.env";
            vpn = {
              enable = false;
              allowUnconfined = true;
            };
          };
        }).config;
    in
    lib.all (a: a.assertion) direct.assertions
    && !direct.systemd.services.slskd.vpn.enable
    && direct.services.slskd.settings.web.ip_address == "127.0.0.1"
    && !direct.services.slskd.openFirewall;
  customWebPort =
    let
      custom =
        (evaluate {
          imports = [ ../../examples/media-server.nix ];
          homelab.apps.slskd = {
            enable = true;
            credentialsFile = "/run/secrets/slskd.env";
            webPort = 55030;
            peerPort = 55031;
            vpn.allowInbound = true;
          };
        }).config;
    in
    custom.services.slskd.settings.web.port == 55030
    && custom.services.slskd.settings.soulseek.listen_port == 55031
    && builtins.elem 55030 custom.homelab.vpn.namespace.hostIngressPorts.tcp
    && custom.homelab.vpn.inboundPorts.tcp == [ 55031 ];
}
