"""Exercise arr integration with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

import json
import shlex

for name in ("lidarr", "bazarr"):
    machine.wait_for_unit(name + ".service")
    machine.succeed("systemctl start homelab-integrate-" + name)
roots = json.loads(
    machine.succeed(
        "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:8686/api/v1/rootfolder"
    )
)
assert len(roots) == 1, roots
assert roots[0]["name"] == "Music", roots
assert roots[0]["defaultQualityProfileId"] > 0, roots
profiles = json.loads(
    machine.succeed(
        "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:6767/api/system/languages/profiles"
    )
)
assert len(profiles) == 1, profiles
assert profiles[0]["name"] == "English", profiles
settings = json.loads(
    machine.succeed(
        "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:6767/api/system/settings"
    )
)
assert settings["general"]["serie_default_enabled"], settings["general"]
assert settings["general"]["movie_default_enabled"], settings["general"]
assert int(settings["general"]["serie_default_profile"]) == profiles[0]["profileId"], (
    settings["general"]
)
languages = json.loads(
    machine.succeed(
        "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:6767/api/system/languages"
    )
)
assert any(item["code2"] == "en" and item["enabled"] for item in languages), languages
media_url = "http://127.0.0.1:8686/api/v1/config/mediamanagement"
media_settings = json.loads(
    machine.succeed(
        "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' " + media_url
    )
)
assert media_settings["copyUsingHardlinks"], media_settings
assert media_settings["minimumFreeSpaceWhenImporting"] == 20480, media_settings
assert media_settings["rescanAfterRefresh"] == "afterManual", media_settings
naming_url = "http://127.0.0.1:8686/api/v1/config/naming"
naming = json.loads(
    machine.succeed(
        "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' " + naming_url
    )
)
assert naming["renameTracks"], naming
assert "{track:00}" in naming["standardTrackFormat"], naming
handling_url = "http://127.0.0.1:8686/api/v1/config/downloadclient"
curl = "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
handling = json.loads(machine.succeed(curl + handling_url))
assert handling["enableCompletedDownloadHandling"], handling
assert not handling["autoRedownloadFailed"], handling
handling["enableCompletedDownloadHandling"] = False
handling["downloadClientWorkingFolders"] = "_manual_fixture"
machine.succeed(
    curl
    + "-X PUT -H 'Content-Type: application/json' --data "
    + shlex.quote(json.dumps(handling))
    + " "
    + handling_url
)
machine.succeed("systemctl restart homelab-integrate-lidarr homelab-integrate-bazarr")
machine.succeed("systemctl restart lidarr bazarr")
machine.succeed("systemctl restart homelab-integrate-lidarr homelab-integrate-bazarr")
repeated = json.loads(
    machine.succeed(
        "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:6767/api/system/languages/profiles"
    )
)
assert repeated == profiles, repeated
handling = json.loads(machine.succeed(curl + handling_url))
assert handling["enableCompletedDownloadHandling"], handling
assert not handling["autoRedownloadFailed"], handling
assert handling["downloadClientWorkingFolders"] == "_manual_fixture", handling
