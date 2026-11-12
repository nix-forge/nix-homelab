# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/scripts/media project/tests/media
cp @pyproject_toml@ project/pyproject.toml
cp @scripts_media_lyrics_py@ project/scripts/media/lyrics.py
cp @tests_media_test_lyrics_py@ project/tests/media/test_lyrics.py
cp @scripts_media_artwork_py@ project/scripts/media/artwork.py
cp @scripts_media_configure_moonbase_py@ project/scripts/media/configure_moonbase.py
cp @tests_media_test_artwork_py@ project/tests/media/test_artwork.py
cp -R @tests_media_fixtures@ project/tests/media/fixtures
cp @tests_media_test_configure_moonbase_py@ project/tests/media/test_configure_moonbase.py
cp @scripts_media_configure_captions_py@ project/scripts/media/configure_captions.py
cp @scripts_media_configure_music_shuffle_py@ project/scripts/media/configure_music_shuffle.py
cp @tests_media_test_captions_py@ project/tests/media/test_captions.py
cp @tests_media_test_music_shuffle_py@ project/tests/media/test_music_shuffle.py
cd project || exit
python3 -B -m pytest -q tests/media
touch "$out"
