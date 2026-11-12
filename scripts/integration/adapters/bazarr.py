"""Reconcile Bazarr settings and language profiles."""

import copy
import json

from common import ConfigurationError


def _merge_profile_items(current_items, declared_items):
    """Apply declared item fields while retaining fields supplied by Bazarr.

    Returns:
        Merged language items in declared order.

    """
    by_id = {item.get("id"): item for item in current_items}
    merged = []
    for item in declared_items:
        current = by_id.get(item.get("id"))
        if current and current.get("language") == item.get("language"):
            merged.append({**current, **item})
        else:
            merged.append(item)
    return merged


def reconcile_bazarr(client, config, dry_run):
    current = client.request("GET", "/api/system/settings")
    if config["mode"] == "bootstrap":
        return {"unchanged": True}
    changed = {}
    settings = config.get("settings", {})
    for section, fields in settings.items():
        if section in {
            "languageProfiles",
            "enabledLanguages",
            "defaultProfiles",
            "seriesTypeProfiles",
        }:
            continue
        if section not in current or not isinstance(fields, dict):
            raise ConfigurationError("Unknown subtitle settings section")
        for key, declared_value in fields.items():
            if key not in current[section]:
                raise ConfigurationError(f"Unknown subtitle setting {section}.{key}")
            if current[section][key] != declared_value:
                normalized_value = (
                    str(declared_value).lower()
                    if isinstance(declared_value, bool)
                    else declared_value
                )
                changed[f"settings-{section}-{key}"] = normalized_value
    if (
        settings.get("languageProfiles")
        or settings.get("defaultProfiles")
        or settings.get("seriesTypeProfiles")
    ):
        profiles = client.request("GET", "/api/system/languages/profiles")
        desired = copy.deepcopy(profiles)
        next_id = max((item["profileId"] for item in profiles), default=0) + 1
        for name, fields in settings.get("languageProfiles", {}).items():
            allowed = {
                "items",
                "cutoff",
                "mustContain",
                "mustNotContain",
                "originalFormat",
                "tag",
            }
            if not set(fields).issubset(allowed):
                raise ConfigurationError("Unknown subtitle language profile field")
            matches = [item for item in desired if item["name"] == name]
            if len(matches) > 1:
                raise ConfigurationError("Ambiguous subtitle language profile")
            if matches:
                updated_fields = fields
                if "items" in fields:
                    updated_fields = {
                        **fields,
                        "items": _merge_profile_items(
                            matches[0].get("items", []), fields["items"]
                        ),
                    }
                matches[0].update(updated_fields)
            else:
                if not fields.get("items"):
                    raise ConfigurationError("New subtitle profiles require languages")
                desired.append({
                    "profileId": next_id,
                    "name": name,
                    "cutoff": None,
                    "mustContain": "",
                    "mustNotContain": "",
                    "originalFormat": False,
                    "tag": None,
                    **fields,
                })
                next_id += 1
        if desired != profiles:
            # Bazarr replaces this collection. Preserve every undeclared profile.
            changed["languages-profiles"] = json.dumps(desired)
        for kind, name in settings.get("defaultProfiles", {}).items():
            if kind not in {"series", "movies"}:
                raise ConfigurationError("Unknown subtitle default profile target")
            matches = [item for item in desired if item["name"] == name]
            if len(matches) != 1:
                raise ConfigurationError(
                    "Subtitle default profile is missing or ambiguous"
                )
            prefix = "serie" if kind == "series" else "movie"
            for key, value in {
                prefix + "_default_enabled": True,
                prefix + "_default_profile": matches[0]["profileId"],
            }.items():
                if key not in current["general"]:
                    raise ConfigurationError("Unknown subtitle default profile setting")
                if current["general"][key] != value:
                    changed["settings-general-" + key] = (
                        str(value).lower() if isinstance(value, bool) else value
                    )
    if settings.get("enabledLanguages"):
        languages = client.request("GET", "/api/system/languages")
        requested = set(settings["enabledLanguages"])
        if not requested.issubset({item["code2"] for item in languages}):
            raise ConfigurationError("Unknown subtitle language code")
        enabled = {item["code2"] for item in languages if item["enabled"]}
        if not requested.issubset(enabled):
            # This endpoint replaces enabled languages; retain manual selections.
            changed["languages-enabled"] = sorted(enabled | requested)
    if changed and not dry_run:
        client.request("POST", "/api/system/settings", changed, form=True)
    series_changes = 0
    series = (
        client.request("GET", "/api/series")["data"]
        if settings.get("seriesTypeProfiles")
        else []
    )
    for series_type, profile_name in settings.get("seriesTypeProfiles", {}).items():
        if series_type not in {"anime", "standard", "daily"}:
            raise ConfigurationError("Unknown subtitle series type")
        matches = [item for item in desired if item["name"] == profile_name]
        if len(matches) != 1:
            raise ConfigurationError(
                "Subtitle series-type profile is missing or ambiguous"
            )
        profile_id = matches[0]["profileId"]
        for item in series:
            if item["seriesType"] != series_type or item["profileId"] == profile_id:
                continue
            series_changes += 1
            if not dry_run:
                client.request(
                    "POST",
                    "/api/series",
                    {"seriesid": item["sonarrSeriesId"], "profileid": profile_id},
                    form=True,
                )
    return {"changed": len(changed) + series_changes}
