# IDs from the exact TRaSH Guides revision in resources.nix.
# Native profiles keep undeclared scores; dual audio and subtitle labels are opt-in.
app: profile: preferAnimeDualAudio: preferSubtitleLabeledReleases:
let
  profiles = if builtins.isList profile then profile else [ profile ];
in
[
  {
    trash_ids =
      {
        radarr = [
          "90a6f9a284dff5103f6346090e6280c8" # LQ
          "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
          "ed38b889b31be83fda192888e2286d83" # BR-DISK
          "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
          "e6886871085226c3da1830830146846c" # Generated Dynamic HDR
        ];
        sonarr = [
          "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
          "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)
          "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
          "23297a736ca77c0fc8e70f8edd7ee56c" # Upscaled
          "e6886871085226c3da1830830146846c" # Generated Dynamic HDR, shared guide rules
        ];
      }
      .${app};
    assign_scores_to = map (name: {
      inherit name;
      score = -10000;
    }) profiles;
  }
  # "Do Not Prefer" for native Propers/Repacks needs these guide scores so
  # corrected releases can win within the same quality when upgrades are on.
  {
    trash_ids = [
      {
        radarr = "e7718d7a3ce595f289bfee26adc178f5";
        sonarr = "ec8fa7296b64e8cd390a1600981f3923";
      }
      .${app}
    ];
    assign_scores_to = map (name: {
      inherit name;
      score = 5;
    }) profiles;
  }
  {
    trash_ids = [
      {
        radarr = "ae43b294509409a6a13919dedd4764c4";
        sonarr = "eb3d5cc0a2be0db205fb823640db6a3c";
      }
      .${app}
    ];
    assign_scores_to = map (name: {
      inherit name;
      score = 6;
    }) profiles;
  }
  {
    trash_ids = [
      {
        radarr = "5caaaa1c08c1742aa4342d8c4cc463f2";
        sonarr = "44e7c4de10ae50265753082e5dc76047";
      }
      .${app}
    ];
    assign_scores_to = map (name: {
      inherit name;
      score = 7;
    }) profiles;
  }
]
++ (
  if app == "sonarr" && preferAnimeDualAudio then
    [
      {
        trash_ids = [ "418f50b10f1907201b6cfdf881f467b7" ]; # Anime Dual Audio
        assign_scores_to = map (name: {
          inherit name;
          score = 10;
        }) profiles;
      }
    ]
  else
    [ ]
)
++ (
  if app == "sonarr" && preferSubtitleLabeledReleases then
    [
      {
        trash_ids = [ "2e651e2224c147819603274f85cff2f7" ];
        assign_scores_to = [
          {
            name = "Homelab 1080p";
            score = 100;
          }
        ];
      }
    ]
  else
    [ ]
)

# Audio stays below HDR preference; none of these codecs is required.
++
  map
    (format: {
      trash_ids = [ format.${app} ];
      assign_scores_to = map (name: {
        inherit name;
        inherit (format) score;
      }) profiles;
    })
    [
      {
        # truehd-atmos
        radarr = "496f355514737f7d83bf7aa4d24f8169";
        sonarr = "0d7824bb924701997f874e7ff7d4844a";
        score = 500;
      }
      {
        # dts-x
        radarr = "2f22d89048b01681dde8afe203bf2e95";
        sonarr = "9d00418ba386a083fbf4d58235fc37ef";
        score = 450;
      }
      {
        # ddplus-atmos
        radarr = "1af239278386be2919e1bcee0bde047e";
        sonarr = "4232a509ce60c4e208d13825b7c06264";
        score = 400;
      }
      {
        # truehd
        radarr = "3cafb66171b47f226146a0770576870f";
        sonarr = "1808e4b9cee74e064dfae3f1db99dbfe";
        score = 350;
      }
      {
        # dts-hd-ma
        radarr = "dcf3ec6938fa32445f590a4da84256cd";
        sonarr = "c429417a57ea8c41d57e6990a8b0033f";
        score = 300;
      }
      {
        # flac
        radarr = "a570d4a0e56a2874b64e5bfa55202a1b";
        sonarr = "851bd64e04c9374c51102be3dd9ae4cc";
        score = 250;
      }
      {
        # pcm
        radarr = "e7c2fcae07cbada050a0af3357491d7b";
        sonarr = "30f70576671ca933adbdcfc736a69718";
        score = 250;
      }
      {
        # atmos-undefined
        radarr = "417804f7f2c4308c1f4c5d380d4c4475";
        sonarr = "b6fbafa7942952a13e17e2b1152b539a";
        score = 150;
      }
      {
        # dts-hd-hra
        radarr = "8e109e50e0a0b83a5098b056e13bf6db";
        sonarr = "cfa5fbd8f02a86fc55d8d223d06a5e1f";
        score = 140;
      }
      {
        # ddplus
        radarr = "185f1dd7264c4562b9022d963ac37424";
        sonarr = "63487786a8b01b7f20dd2bc90dd4a477";
        score = 100;
      }
      {
        # dts-es
        radarr = "f9f847ac70a0af62ea4a08280b859636";
        sonarr = "c1a25cd67b5d2e08287c957b1eb903ec";
        score = 90;
      }
      {
        # dts
        radarr = "1c1a4c5e823891c75bc50380a6866f73";
        sonarr = "5964f2a8b3be407d083498e4459d05d0";
        score = 80;
      }
      {
        # aac
        radarr = "240770601cc226190c367ef59aba7463";
        sonarr = "a50b8a0c62274a7c38b09a9619ba9d86";
        score = 60;
      }
      {
        # dd
        radarr = "c2998bd0d90ed5621d8df281e839436e";
        sonarr = "dbe00161b08a25ac6154c55f95e6318d";
        score = 50;
      }
    ]
