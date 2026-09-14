{
  flake = {
    lib.version = "0.1.0-dev";
    templates.default = {
      path = ../templates/minimal;
      description = "Minimal pinned nix-homelab NixOS configuration";
    };
  };
}
