{ pkgs }:
let
  applicationConfig = pkgs.writeText "phpstan-freshrss.neon" ''
    parameters:
        scanDirectories:
            - ${pkgs.freshrss}/app
            - ${pkgs.freshrss}/lib
        scanFiles:
            - ${pkgs.freshrss}/cli/_cli.php
  '';
in
pkgs.writeShellApplication {
  name = "homelab-phpstan";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.phpstan
  ];
  text = (import ../../lib/render-text.nix) ./scripts/phpstan.sh.in { inherit applicationConfig; };
}
