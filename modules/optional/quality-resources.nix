# Reviewed policy resources are fixed Nix inputs; the service never follows a branch.
{ pkgs }: [
  {
    name = "homelab-trash-guides";
    type = "trash-guides";
    replace_default = true;
    path = pkgs.fetchzip {
      url = "https://github.com/TRaSH-Guides/Guides/archive/a9486f6465d4483993dec638131272b397a4338e.tar.gz";
      hash = "sha256-UOWPibxjhNvIdEKFLqQ+aXHzFWEmGZhxgzpsaq5XjBw=";
    };
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
]
