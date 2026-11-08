CREATE TABLE album (id TEXT, mbz_release_group_id TEXT, missing INT);

CREATE TABLE media_file (path TEXT, album_id TEXT, missing INT);

INSERT INTO
  album
VALUES
  ('known', 'group-a', 0),
  ('unknown', '', 0);

INSERT INTO
  media_file
VALUES
  ('shared/a.flac', 'known', 0),
  ('shared/b.flac', 'unknown', 0);
