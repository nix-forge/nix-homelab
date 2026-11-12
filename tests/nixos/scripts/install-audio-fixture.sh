# shellcheck shell=bash
install -m 0640 -o root -g media @audio@/fixture.flac /srv/media/library/music/fixture.flac
install -d -m 2770 -o root -g media /srv/media/library/audiobooks/Fixture
install -m 0640 -o root -g media @audio@/fixture.flac /srv/media/library/audiobooks/Fixture/fixture.flac
