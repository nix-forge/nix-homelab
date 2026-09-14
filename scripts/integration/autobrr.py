"""Named autobrr 1.84 API resources; provider accounts remain host-owned."""

import copy
import hashlib
import hmac
import json
import os
import secrets
from pathlib import Path
from urllib.parse import urlsplit

CLIENT_TYPES = {"QBITTORRENT", "SONARR", "RADARR", "LIDARR", "SABNZBD", "NZBGET"}
CLIENT_FIELDS = {
    "type",
    "enabled",
    "host",
    "port",
    "tls",
    "tls_skip_verify",
    "username",
    "password",
    "settings",
}
# Native Store explicitly inserts SQL arrays; omitted slices become NULL and fail.
FILTER_ARRAY_DEFAULTS = {
    name: []
    for name in (
        "resolutions",
        "codecs",
        "sources",
        "containers",
        "match_hdr",
        "except_hdr",
        "match_other",
        "except_other",
        "match_language",
        "except_language",
        "match_release_types",
        "formats",
        "quality",
        "media",
        "origins",
        "except_origins",
    )
}
FILTER_FIELDS = {
    "enabled",
    "min_size",
    "max_size",
    "delay",
    "priority",
    "max_downloads",
    "max_downloads_unit",
    "match_releases",
    "except_releases",
    "use_regex",
    "match_release_groups",
    "except_release_groups",
    "announce_types",
    "scene",
    "freeleech",
    "freeleech_percent",
    "smart_episode",
    "shows",
    "seasons",
    "episodes",
    "resolutions",
    "codecs",
    "sources",
    "containers",
    "match_hdr",
    "except_hdr",
    "years",
    "artists",
    "albums",
    "formats",
    "quality",
    "media",
    "match_categories",
    "except_categories",
    "match_uploaders",
    "except_uploaders",
    "match_language",
    "except_language",
    "tags",
    "except_tags",
    "min_seeders",
    "max_seeders",
}
ACTION_FIELDS = {
    "type",
    "enabled",
    "category",
    "tags",
    "label",
    "save_path",
    "download_path",
    "paused",
    "ignore_rules",
    "first_last_piece_prio",
    "skip_hash_check",
    "content_layout",
    "limit_upload_speed",
    "limit_download_speed",
    "limit_ratio",
    "limit_seed_time",
    "priority",
    "reannounce_skip",
    "reannounce_delete",
    "reannounce_interval",
    "reannounce_max_attempts",
    "external_download_client_id",
    "external_download_client",
}


def named(items, name, **scope):
    matches = [
        item
        for item in items
        if item.get("name") == name and all(item.get(k) == v for k, v in scope.items())
    ]
    if len(matches) > 1:
        raise ValueError("Ambiguous autobrr resource identity")
    return matches[0] if matches else None


def merge(current, values):
    result = copy.deepcopy(current)
    for key, value in values.items():
        result[key] = (
            merge(result.get(key, {}), value)
            if isinstance(value, dict)
            else copy.deepcopy(value)
        )
    return result


def fingerprint(value, previous=None):
    if isinstance(previous, str) and previous.startswith("scrypt:"):
        _, salt, _ = previous.split(":")
    else:
        salt = secrets.token_hex(16)
    digest = hashlib.scrypt(
        str(value).encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1
    ).hex()
    return f"scrypt:{salt}:{digest}"


def fingerprints(value, known=None, prefix=""):
    result = {}
    for key, item in value.items():
        path = prefix + key
        if isinstance(item, dict):
            result.update(fingerprints(item, known, path + "."))
        elif key.lower() in {"password", "apikey"}:
            result[path] = fingerprint(item, (known or {}).get(path))
    return result


def matches(current, values, known=None, prefix=""):
    for key, value in values.items():
        actual = current.get(key)
        if isinstance(value, dict):
            if not matches(actual or {}, value, known, prefix + key + "."):
                return False
        elif key.lower() in {"password", "apikey"}:
            previous = (known or {}).get(prefix + key)
            digest = fingerprint(value, previous)
            if not (
                (isinstance(actual, str) and not actual and not value)
                or (
                    actual
                    and isinstance(previous, str)
                    and hmac.compare_digest(previous, digest)
                )
            ):
                return False
        else:
            default = (
                False
                if isinstance(value, bool)
                else 0
                if isinstance(value, (int, float))
                else []
                if isinstance(value, list)
                else ""
            )
            if (actual if actual is not None else default) != value:
                return False
    return True


def save_state(path, state):
    temporary = path.with_suffix(".tmp")
    with open(
        temporary,
        "w",
        encoding="utf-8",
        opener=lambda name, flags: os.open(name, flags, 0o600),
    ) as handle:
        json.dump(state, handle)
    temporary.replace(path)


def validate(settings):
    if set(settings) - {"downloadClients", "filters"}:
        raise ValueError("Unknown autobrr configuration section")
    for name, values in settings.get("downloadClients", {}).items():
        if (
            not name
            or set(values) - CLIENT_FIELDS
            or values.get("type") not in CLIENT_TYPES
            or not values.get("host")
        ):
            raise ValueError("Invalid autobrr downloader declaration")
        parsed = urlsplit(
            values["host"] if "://" in values["host"] else "http://" + values["host"]
        )
        if (
            parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or parsed.scheme not in {"http", "https"}
        ):
            raise ValueError("Downloader hosts must not embed credentials")
        if (
            values["type"] == "QBITTORRENT"
            and "://" in values["host"]
            and (parsed.scheme == "https") != (values.get("tls", False) is True)
        ):
            raise ValueError(
                "qBittorrent URL scheme must agree with its explicit TLS setting"
            )
        if values.get("tls_skip_verify"):
            raise ValueError(
                "Downloader TLS certificate verification must remain enabled"
            )
    for name, spec in settings.get("filters", {}).items():
        values = spec.get("values", {})
        if (
            not name
            or set(spec) - {"values", "indexers", "actions"}
            or set(values) - FILTER_FIELDS
        ):
            raise ValueError("Invalid autobrr filter declaration")
        if not isinstance(values.get("enabled"), bool):
            raise TypeError("Filter declarations require an explicit enabled boolean")
        if values["enabled"]:
            if (
                not spec.get("indexers")
                or not values.get("max_size")
                or values.get("max_downloads", 0) <= 0
                or values.get("max_downloads_unit")
                not in {"HOUR", "DAY", "WEEK", "MONTH"}
            ):
                raise ValueError(
                    "Enabled filters require explicit indexers and size/download limits"
                )
            if not any(
                values.get(key)
                for key in (
                    "match_releases",
                    "match_categories",
                    "shows",
                    "artists",
                    "albums",
                )
            ):
                raise ValueError(
                    "Enabled filters require an explicit content selection"
                )
        for action_name, action in spec.get("actions", {}).items():
            fields = set(action) - {"client"}
            if (
                not action_name
                or fields - ACTION_FIELDS
                or action.get("type") not in CLIENT_TYPES | {"TEST"}
            ):
                raise ValueError("Invalid autobrr action declaration")
            if action["type"] != "TEST" and not action.get("client"):
                raise ValueError("Downloader actions require a named client")


def reconcile(client, config, dry_run):
    settings = config.get("settings", {})
    validate(settings)
    client.headers = {"X-API-Token": config["apiKey"]}
    clients = client.request("GET", "/api/download_clients") or []
    filters = client.request("GET", "/api/filters") or []
    indexers = client.request("GET", "/api/indexer") or []
    state_path = Path(os.environ["STATE_DIRECTORY"]) / "autobrr-password-state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    counts = {"created": 0, "updated": 0, "unchanged": 0}
    for name, values in settings.get("downloadClients", {}).items():
        current = named(clients, name)
        if current and current["type"] != values["type"]:
            raise ValueError("Existing downloader type cannot be replaced")
        if current and (
            config["mode"] == "bootstrap"
            or matches(current, values, state.get(str(current["id"])))
        ):
            counts["unchanged"] += 1
            continue
        desired = merge(current or {"enabled": False}, {**values, "name": name})
        counts["updated" if current else "created"] += 1
        if dry_run:
            desired.setdefault("id", -len(clients) - 1)
            if not current:
                clients.append(desired)
        else:
            saved = client.request(
                "PUT" if current else "POST", "/api/download_clients", desired
            )
            if not current:
                clients.append(saved)
            state[str(saved["id"])] = fingerprints(values, state.get(str(saved["id"])))
            save_state(state_path, state)
    for name, spec in settings.get("filters", {}).items():
        current = named(filters, name)
        if current and config["mode"] == "bootstrap":
            counts["unchanged"] += 1
            continue
        # Native list actions omit filter_id; the filter detail owns association.
        if current:
            current = client.request("GET", f"/api/filters/{current['id']}")
        values = spec.get("values", {})
        selected = []
        for indexer_name in spec.get("indexers", []):
            indexer = named(indexers, indexer_name)
            if not indexer:
                raise ValueError(
                    "Autobrr indexer is missing; configure its provider account first"
                )
            selected.append(indexer["id"])
        for action in spec.get("actions", {}).values():
            if action.get("client"):
                target = named(clients, action["client"])
                if not target or target["type"] != action["type"]:
                    raise ValueError(
                        "Autobrr action client is missing or has a different type"
                    )
        created = current is None
        if created:
            counts["created"] += 1
            body = {
                **copy.deepcopy(FILTER_ARRAY_DEFAULTS),
                **values,
                "name": name,
                "enabled": False,
            }
            current = (
                {**body, "id": -len(filters) - 1}
                if dry_run
                else client.request("POST", "/api/filters", body)
            )
            filters.append(current)
        current_indexers = current.get("indexers")
        if not isinstance(current_indexers, list):
            current_indexers = []
        current_ids = {item["id"] for item in current_indexers}
        desired_ids = current_ids | set(selected)
        policy = {key: value for key, value in values.items() if key != "enabled"}
        if desired_ids != current_ids:
            policy["indexers"] = [{"id": value} for value in sorted(desired_ids)]
        policy_changed = created or not matches(current, policy)
        current_actions = current.get("actions")
        if not isinstance(current_actions, list):
            current_actions = []
        actions = [{**action, "filter_id": current["id"]} for action in current_actions]
        planned = []
        for action_name, action in spec.get("actions", {}).items():
            existing = named(actions, action_name, filter_id=current["id"])
            declared = {key: value for key, value in action.items() if key != "client"}
            declared.update({"name": action_name, "filter_id": current["id"]})
            if action.get("client"):
                declared["client_id"] = named(clients, action["client"])["id"]
            if existing and existing["type"] != declared["type"]:
                raise ValueError("Existing autobrr action type cannot be replaced")
            if not existing or not matches(existing, declared):
                planned.append((existing, declared))
        desired_enabled = values.get("enabled", current.get("enabled", False))
        changed = (
            policy_changed
            or planned
            or current.get("enabled", False) != desired_enabled
        )
        if not changed:
            counts["unchanged"] += 1
            continue
        if not created:
            counts["updated"] += 1
        if not dry_run:
            # No filter processes announcements while its associations change.
            client.request(
                "PATCH", f"/api/filters/{current['id']}", {**policy, "enabled": False}
            )
        for existing, declared in planned:
            counts["updated" if existing else "created"] += 1
            if not dry_run:
                body = merge(existing or {}, declared)
                client.request(
                    "PUT" if existing else "POST",
                    "/api/actions" + (f"/{existing['id']}" if existing else ""),
                    body,
                )
        if desired_enabled and not dry_run:
            client.request("PATCH", f"/api/filters/{current['id']}", {"enabled": True})
    return counts
