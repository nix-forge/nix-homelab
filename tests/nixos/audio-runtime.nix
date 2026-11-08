{ homelabModule }: {
  name = "homelab-audio-runtime";
  nodes.machine =
    { pkgs, lib, ... }:
    let
      audio = pkgs.runCommand "public-audio-fixture" { nativeBuildInputs = [ pkgs.ffmpeg ]; } (
        builtins.readFile ./scripts/public-audio-fixture.sh
      );
    in
    {
      imports = [
        homelabModule
        ../../examples/audio.nix
      ];
      system.stateVersion = "26.05";
      virtualisation.memorySize = 2048;
      environment.systemPackages = [ pkgs.python3 ];
      environment.etc."audio-fixture.flac".source = "${audio}/fixture.flac";
      systemd.services = {
        audio-fixture = {
          wantedBy = [ "multi-user.target" ];
          before = [
            "navidrome.service"
            "audiobookshelf.service"
            "homelab-integrate-navidrome.service"
            "homelab-integrate-audiobookshelf.service"
          ];
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          script = builtins.readFile ./scripts/prepare-audio-credentials.sh;
        };
        homelab-storage.script = lib.mkAfter (
          (import ../../lib/render-text.nix) ./scripts/install-audio-fixture.sh { inherit audio; }
        );
        navidrome.requires = [ "audio-fixture.service" ];
        audiobookshelf.requires = [ "audio-fixture.service" ];
      };
      homelab.integration.services.navidrome.after = [ "audio-fixture.service" ];
      homelab.integration.services.audiobookshelf.after = [ "audio-fixture.service" ];
    };
  testScript = (import ../../lib/render-text.nix) ./scripts/audio_runtime_test.py {
    fixtures_audio_runtime_py = ../fixtures/audio_runtime.py;
  };
}
