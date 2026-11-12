CREATE TABLE album (
  id TEXT,
  name TEXT,
  album_artist TEXT,
  min_year INT,
  mbz_release_group_id TEXT,
  missing INT
);

CREATE TABLE media_file (path TEXT, album_id TEXT, missing INT);

INSERT INTO
  album
VALUES
  (
    'known',
    'Known',
    'Artist',
    2023,
    'group-known',
    0
  );

INSERT INTO
  album
VALUES
  ('unknown', 'New Album', 'Artist', 2024, '', 0);

INSERT INTO
  media_file
VALUES
  ('known/a.flac', 'known', 0),
  ('new/b.flac', 'unknown', 0);
