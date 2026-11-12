"""Read native Arr API state to verify quality policy changes and preservation."""

import json
import math
import operator
import re
import sys
import urllib.parse
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
        for name in ("Homelab 1080p", "Homelab 2160p"):
            assert name in profiles
            prefer_subtitles = port == "8989" and name == "Homelab 1080p"
            assert profiles[name]["upgradeAllowed"]
            assert profiles[name]["cutoffFormatScore"] == 10000
            assert profiles[name]["minFormatScore"] == 0
            scores = {
                item["format"]: item["score"] for item in profiles[name]["formatItems"]
            }
            for excluded in (
                "LQ",
                "LQ (Release Title)",
                "BR-DISK",
                "Upscaled",
                "Generated Dynamic HDR",
                "DV (w/o HDR fallback)",
            ):
                assert scores[formats[excluded]["id"]] == -10000
            for label, expected in (
                ("Repack/Proper", 5),
                ("Repack2", 6),
                ("Repack3", 7),
            ):
                assert scores[formats[label]["id"]] == expected, (port, name, label)
            if prefer_subtitles:
                subtitle_format = formats["Explicit Subtitle Label"]
                assert scores[subtitle_format["id"]] == 100
                assert subtitle_format["includeCustomFormatWhenRenaming"]
                expression = next(
                    field["value"]
                    for field in subtitle_format["specifications"][0]["fields"]
                    if field["name"] == "value"
                )
                pattern = re.compile(expression)
                assert pattern.search("One Piece 1169 [MultiSub]")
                assert pattern.search("One Piece 1169 (English-Sub)")
                assert not pattern.search("Example Anime 1170 (Japanese Sub)")
                assert not pattern.search("One Piece 1169 TVER WEB-DL")
                assert not pattern.search("[SubsPlease] One Piece 1169")
        if port == "8989":
            anime = profiles["Homelab Anime"]
            anime_qualities = [q for q in anime["items"] if q["allowed"]]
            assert anime_qualities[-1]["name"] == "Bluray 1080p"
            assert {q["quality"]["name"] for q in anime_qualities[-1]["items"]} == {
                "Bluray-1080p",
                "Bluray-1080p Remux",
            }
            assert not any(
                "2160p" in q.get("name", q.get("quality", {}).get("name", ""))
                for q in anime_qualities
            )
            anime_scores = {q["name"]: q["score"] for q in anime["formatItems"]}
            assert anime_scores["Anime Web Tier 01"] > anime_scores["Anime Web Tier 06"]
            assert anime_scores["Anime LQ Groups"] < 0
            assert anime_scores["Upscaled"] == -10000
        # Exercise real release parsing, including rejection despite bonuses.
        profile = profiles["Homelab 2160p"]
        scores = {item["format"]: item["score"] for item in profile["formatItems"]}
        prefix = "Example.Movie.2025" if port == "7878" else "Example.Series.S01E01"

        def score(suffix, port=port, prefix=prefix, scores=scores):
            parsed = api(port, "parse?title=" + urllib.parse.quote(prefix + suffix))
            return sum(scores[item["id"]] for item in parsed["customFormats"])

        sdr = score(".2160p.WEB-DL.HEVC-GROUP")
        hdr = score(".2160p.WEB-DL.HDR.HEVC-GROUP")
        dv = score(".2160p.WEB-DL.DV.HDR.HEVC-GROUP")
        plus = score(".2160p.WEB-DL.HDR10Plus.HEVC-GROUP")
        atmos = score(".2160p.WEB-DL.HDR.TrueHD.Atmos.7.1.HEVC-GROUP")
        assert sdr >= profile["minFormatScore"]
        assert hdr > sdr
        assert dv > hdr
        assert plus > hdr
        assert atmos > hdr
        assert score(".2160p.WEB-DL.DV.HEVC-GROUP") < profile["minFormatScore"]
        assert score(".2160p.Upscaled.WEB-DL.DV.HDR.TrueHD.Atmos.HEVC-GROUP") < 0
        assert score(".2160p.WEB-DL.DV.HDR.HEVC-BiTOR") < 0
        allowed = [item for item in profile["items"] if item["allowed"]]
        highest = allowed[-1]["quality"]["name"]
        assert highest == ("Remux-2160p" if port == "7878" else "Bluray-2160p Remux")
        definitions = {item["quality"]["name"]: item for item in current["definitions"]}
        # Arr caches size definitions for five seconds. Match independent
        # guide values before capturing state for the repeated-sync check.
        assert math.isclose(
            definitions["WEBDL-2160p"]["minSize"], 34.5 if port == "7878" else 25
        )
        assert math.isclose(
            definitions["WEBDL-1080p"]["minSize"], 12.5 if port == "7878" else 15
        )
        assert (
            definitions[highest].get("maxSize") is None
            or definitions[highest]["maxSize"] >= 500
        )
    Path("/tmp/quality-applied.json").write_text(json.dumps(state), encoding="utf-8")
elif sys.argv[1] == "manual-score":
    for port, current in state.items():
        manual = next(
            item
            for item in current["formats"]
            if item["name"] == "Manual fixture format"
        )
        for profile in current["profiles"]:
            if profile["name"] in {"Homelab 1080p", "Homelab 2160p"}:
                for item in profile["formatItems"]:
                    if item["format"] == manual["id"]:
                        item["score"] = 37
                api(port, f"qualityprofile/{profile['id']}", profile, "PUT")
    Path("/tmp/quality-applied.json").write_text(json.dumps(state), encoding="utf-8")
elif sys.argv[1] == "repeat":
    expected = json.loads(Path("/tmp/quality-applied.json").read_text(encoding="utf-8"))
    for snapshot in (state, expected):
        for current in snapshot.values():
            for profile in current["profiles"]:
                # CF array order is presentation, unlike quality precedence.
                profile["formatItems"].sort(key=operator.itemgetter("format"))
    for port, current in state.items():
        for section, actual in current.items():
            assert actual == expected[port][section], (
                port,
                section,
                actual,
                expected[port][section],
            )
print("Native quality state verified:", sys.argv[1])
