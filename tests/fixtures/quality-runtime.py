"""Read native Arr API state to verify quality policy changes and preservation."""

import json
import sys
import urllib.request
from pathlib import Path

KEY = "0123456789abcdef0123456789abcdef"


def api(port, endpoint, body=None, method=None):
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/api/v3/{endpoint}",
        headers={"X-Api-Key": KEY, "Content-Type": "application/json"},
        data=None if body is None else json.dumps(body).encode(),
        method=method,
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)


if sys.argv[1] == "before":
    for port in (7878, 8989):
        manual = api(
            port,
            "customformat",
            {
                "name": "Manual fixture format",
                "includeCustomFormatWhenRenaming": False,
                "specifications": [
                    {
                        "name": "Manual fixture expression",
                        "implementation": "ReleaseTitleSpecification",
                        "negate": False,
                        "required": False,
                        "fields": [{"name": "value", "value": "UnmanagedFixtureOnly"}],
                    }
                ],
            },
            "POST",
        )
        profile = api(port, "qualityprofile")[0]
        for item in profile["formatItems"]:
            if item["format"] == manual["id"]:
                item["score"] = 37
        api(port, f"qualityprofile/{profile['id']}", profile, "PUT")

state = {}
for port in (7878, 8989):
    profiles = api(port, "qualityprofile")
    definitions = api(port, "qualitydefinition")
    state[str(port)] = {
        "profiles": profiles,
        "definitions": definitions,
        "formats": api(port, "customformat"),
    }

path = Path("/tmp/quality-state.json")
if sys.argv[1] == "before":
    path.write_text(json.dumps(state), encoding="utf-8")
elif sys.argv[1] == "preview":
    assert state == json.loads(path.read_text(encoding="utf-8")), (
        "Preview changed Arr configuration"
    )
elif sys.argv[1] == "applied":
    before = json.loads(path.read_text(encoding="utf-8"))
    for port, current in state.items():
        profiles = {item["name"]: item for item in current["profiles"]}
        for old in before[port]["profiles"]:
            actual = profiles[old["name"]]
            assert {k: v for k, v in actual.items() if k != "formatItems"} == {
                k: v for k, v in old.items() if k != "formatItems"
            }, "Undeclared native profile changed"
            scores = {item["format"]: item["score"] for item in actual["formatItems"]}
            assert all(
                scores[item["format"]] == item["score"] for item in old["formatItems"]
            )
        formats = {item["name"]: item for item in current["formats"]}
        assert formats["Manual fixture format"] == before[port]["formats"][0]
        for name in ("Homelab 1080p", "Homelab 4K WEB"):
            assert name in profiles
            assert not profiles[name]["upgradeAllowed"]
            assert profiles[name]["minFormatScore"] == 0
            scores = {
                item["format"]: item["score"] for item in profiles[name]["formatItems"]
            }
            for excluded in ("LQ", "LQ (Release Title)", "BR-DISK"):
                assert scores[formats[excluded]["id"]] == -10000
        definitions = {item["quality"]["name"]: item for item in current["definitions"]}
        for name in ("WEBDL-1080p", "WEBRip-1080p"):
            assert definitions[name]["minSize"] == 5, (port, name, definitions[name])
            assert definitions[name]["preferredSize"] == 40
            assert definitions[name]["maxSize"] == 80
        for name in ("WEBDL-2160p", "WEBRip-2160p"):
            assert definitions[name]["minSize"] == 10
            assert definitions[name]["preferredSize"] == 80
            assert definitions[name]["maxSize"] == 160
    Path("/tmp/quality-applied.json").write_text(json.dumps(state), encoding="utf-8")
elif sys.argv[1] == "manual-score":
    for port, current in state.items():
        manual = next(
            item
            for item in current["formats"]
            if item["name"] == "Manual fixture format"
        )
        for profile in current["profiles"]:
            if profile["name"] in {"Homelab 1080p", "Homelab 4K WEB"}:
                for item in profile["formatItems"]:
                    if item["format"] == manual["id"]:
                        item["score"] = 37
                api(port, f"qualityprofile/{profile['id']}", profile, "PUT")
    Path("/tmp/quality-applied.json").write_text(json.dumps(state), encoding="utf-8")
elif sys.argv[1] == "repeat":
    assert state == json.loads(
        Path("/tmp/quality-applied.json").read_text(encoding="utf-8")
    )
print("Native quality state verified:", sys.argv[1])
