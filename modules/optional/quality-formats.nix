# IDs from the exact TRaSH Guides revision in quality-resources.nix.
# Native profiles keep undeclared scores; only these exclusions are managed.
app: profile: [
  {
    trash_ids =
      {
        radarr = [
          "90a6f9a284dff5103f6346090e6280c8" # LQ
          "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
          "ed38b889b31be83fda192888e2286d83" # BR-DISK
        ];
        sonarr = [
          "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
          "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)
          "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
        ];
      }
      .${app};
    assign_scores_to = [
      {
        name = profile;
        score = -10000;
      }
    ];
  }
]
