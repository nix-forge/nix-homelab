# Reviewed policy resources are fixed Nix inputs; the service never follows a branch.
{ pkgs }:
let
  guides = pkgs.fetchzip {
    url = "https://github.com/TRaSH-Guides/Guides/archive/a9486f6465d4483993dec638131272b397a4338e.tar.gz";
    hash = "sha256-UOWPibxjhNvIdEKFLqQ+aXHzFWEmGZhxgzpsaq5XjBw=";
  };
in
[
  {
    name = "homelab-trash-guides";
    type = "trash-guides";
    replace_default = true;
    path = guides;
  }
  {
    name = "homelab-config-templates";
    type = "config-templates";
    replace_default = true;
    path = pkgs.fetchzip {
      url = "https://github.com/recyclarr/config-templates/archive/9faf65ff745d74ab906fd73cadaa25f08eb9d981.tar.gz";
      hash = "sha256-4uchNVJHeu3CIPLfmKhYB7cLW9Wu8kTTANVlE/MxxiQ=";
    };
  }
  {
    name = "homelab-sonarr-subtitle-formats";
    type = "custom-formats";
    service = "sonarr";
    path = ./custom-formats;
  }
  {
    # Both managers implement these title/group specifications. Share the
    # pinned Radarr generated-HDR rules rather than maintain a second list.
    name = "homelab-sonarr-generated-hdr";
    type = "custom-formats";
    service = "sonarr";
    path = pkgs.runCommand "sonarr-generated-hdr-formats" { } (
      (import ../../../lib/render-text.nix) ./scripts/sonarr-generated-hdr-formats.sh { inherit guides; }
    );
  }
]
