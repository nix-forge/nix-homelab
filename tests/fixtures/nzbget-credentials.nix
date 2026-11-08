# Disposable VM credentials are public fixtures, never production secrets.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  credentialPath = "/run/nzbget-public-test.conf";
  credentials = (pkgs.formats.keyValue { }).generate "nzbget-public-test.conf" {
    ControlUsername = "fixture";
    ControlPassword = "public-disposable-nzbget-password";
  };
in
{
  config = lib.mkIf config.homelab.apps.nzbget.enable {
    homelab.apps.nzbget.credentialsFile = lib.mkDefault credentialPath;
    systemd.tmpfiles.rules = [ "C ${credentialPath} 0600 root root - ${credentials}" ];
  };
}
