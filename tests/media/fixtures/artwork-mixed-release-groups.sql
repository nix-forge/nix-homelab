CREATE TABLE album (id TEXT, mbz_release_group_id TEXT, missing INT);

CREATE TABLE media_file (path TEXT, album_id TEXT, missing INT);

INSERT INTO
  album
VALUES
  ('a', 'group-a', 0),
  ('b', 'group-b', 0);

INSERT INTO
  media_file
VALUES
  ('mixed/a.flac', 'a', 0),
  ('mixed/b.flac', 'b', 0);
