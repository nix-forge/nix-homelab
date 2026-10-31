# Build representative original state using only the maintained runtime.
Application.load(:pinchflat)

database = System.fetch_env!("DATABASE_PATH")
migrations = System.fetch_env!("LEGACY_MIGRATIONS")
media_file = Path.join(System.fetch_env!("MEDIA_PATH"), "legacy-fixture.txt")

if File.exists?(database), do: raise("fixture database already exists")
File.mkdir_p!(Path.dirname(database))

{:ok, _, _} =
  Ecto.Migrator.with_repo(Pinchflat.Repo, fn repo ->
    Ecto.Migrator.run(repo, migrations, :up, all: true)

    query = fn sql, params ->
      Ecto.Adapters.SQL.query!(repo, sql, params)
    end

    %{rows: [[78, 20250317213740]]} =
      query.("SELECT count(*), max(version) FROM schema_migrations", [])

    %{num_rows: 1} =
      query.("""
      UPDATE settings
      SET onboarding = 0, route_token = ?,
          video_codec_preference = 'vp9', audio_codec_preference = 'opus',
          restrict_filenames = 1
      """, ["synthetic-installation-token"])

    query.("""
    INSERT INTO media_profiles
      (id, name, output_path_template, inserted_at, updated_at)
    VALUES
      (1, 'Legacy fixture', 'fixture/{{ title }}.{{ ext }}',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """, [])

    query.("""
    INSERT INTO sources
      (id, collection_name, custom_name, collection_id, collection_type,
        original_url, media_profile_id, uuid, enabled, download_media,
        inserted_at, updated_at)
    VALUES
      (1, 'Legacy collection', 'Preserved custom name', 'legacy-fixture',
        'playlist', 'https://www.youtube.com/playlist?list=legacy-fixture',
        1, '00000000-0000-4000-8000-000000000001', 0, 0,
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """, [])

    query.("""
    INSERT INTO media_items
      (id, media_id, title, source_id, original_url, media_filepath,
        uuid, inserted_at, updated_at)
    VALUES
      (1, 'legacy-media', 'Preserved media', 1,
        'https://www.youtube.com/watch?v=legacy-media', ?,
        '00000000-0000-4000-8000-000000000002',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """, [media_file])
  end)

File.mkdir_p!(Path.dirname(media_file))
File.write!(media_file, "synthetic legacy media\n")
