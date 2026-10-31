"""Upgrade a representative original SQLite database under the real service."""

import json

# NixOS supplies the live machine object when executing this driver.
machine = globals()["machine"]

machine.wait_for_unit("multi-user.target")
machine.wait_until_succeeds("systemctl is-failed homelab-storage.service")
machine.fail("systemctl is-active pinchflat.service")
machine.fail("test -e /mnt/media/data")
machine.succeed("mkdir -p /mnt/media; mount -t tmpfs tmpfs /mnt/media")
machine.succeed("systemctl reset-failed; systemctl start pinchflat.service")
machine.wait_for_unit("pinchflat.service")
machine.wait_for_open_port(8945)
machine.wait_until_succeeds(
    "curl -fsS --netrc-file /run/pinchflat.netrc http://127.0.0.1:8945/ >/dev/null"
)
machine.succeed("systemctl show pinchflat -p ExecStart --value | grep -F pinchflat-ngx")
machine.succeed(
    "systemctl show pinchflat -p ExecStartPre --value | grep -F pinchflat-ngx"
)
machine.succeed(
    "test $(stat -c %U:%G /var/lib/pinchflat/db/pinchflat.db) = pinchflat:pinchflat"
)
machine.succeed("test $(systemctl show pinchflat -p NoNewPrivileges --value) = yes")


def rows(query):
    return json.loads(
        machine.succeed(f"sqlite3 -json /var/lib/pinchflat/db/pinchflat.db '{query}'")
    )


def assert_preserved():
    settings = rows(
        "SELECT route_token, video_codec_preference, audio_codec_preference, restrict_filenames, onboarding FROM settings"
    )[0]
    assert settings["route_token"] == "synthetic-installation-token"
    assert settings["video_codec_preference"] == "vp9"
    assert settings["audio_codec_preference"] == "opus"
    assert settings["restrict_filenames"] == 1
    assert settings["onboarding"] == 0
    assert rows(
        "SELECT provenance, status, original_max_version, "
        "original_source_count, confirmed_at FROM legacy_migration_records"
    ) == [
        {
            "provenance": "legacy_pinchflat",
            "status": "pending_review",
            "original_max_version": 20250317213740,
            "original_source_count": 1,
            "confirmed_at": None,
        }
    ]
    assert rows("SELECT custom_name_locked FROM sources WHERE id = 1") == [
        {"custom_name_locked": 1}
    ]
    assert (
        rows("SELECT name FROM media_profiles WHERE id = 1")[0]["name"]
        == "Legacy fixture"
    )
    source = rows(
        "SELECT custom_name, enabled, download_media FROM sources WHERE id = 1"
    )[0]
    assert source == {
        "custom_name": "Preserved custom name",
        "enabled": 0,
        "download_media": 0,
    }
    media = rows("SELECT title, media_filepath FROM media_items WHERE id = 1")[0]
    assert media["title"] == "Preserved media"
    assert (
        media["media_filepath"] == "/mnt/media/data/library/videos/legacy-fixture.txt"
    )
    assert (
        rows("SELECT max(version) AS version FROM schema_migrations")[0]["version"]
        > 20250317213740
    )
    machine.succeed(
        "grep -Fx 'synthetic legacy media' /mnt/media/data/library/videos/legacy-fixture.txt"
    )


assert_preserved()
machine.succeed("systemctl restart pinchflat.service")
machine.wait_for_unit("pinchflat.service")
machine.wait_for_open_port(8945)
assert_preserved()
