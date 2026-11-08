"""Reconcile declared application objects without deleting unowned state.

The public interface is a JSON configuration and runtime systemd credentials.
Only bounded HTTP requests are made. Responses and credentials are never logged.
"""

import argparse
import json
import sys
from pathlib import Path

from adapters.arr import reconcile_arr
from adapters.audiobookshelf import reconcile_audiobookshelf
from adapters.bazarr import reconcile_bazarr
from adapters.jellyfin import reconcile_jellyfin
from adapters.navidrome import reconcile_navidrome
from adapters.seerr import reconcile_seerr
from common import (
    APIUnavailableError,
    Client,
    ConfigurationError,
    resolve,
    validate_url,
)


def add_private_indexers(config):
    """Validate and append sealed Prowlarr selections before any API writes.

    Returns:
        Whether a private document was loaded.

    Raises:
        ConfigurationError: The document or a provider route is invalid.

    """
    document = config.pop("privateIndexers", None)
    if document is None:
        return False
    if config.get("kind") != "prowlarr":
        raise ConfigurationError("Private indexers require Prowlarr")
    selected = json.loads(document)
    if not isinstance(selected, dict) or set(selected) != {"indexers"}:
        raise ConfigurationError("Invalid private indexer document")
    indexers = selected["indexers"]
    if not isinstance(indexers, list):
        raise ConfigurationError("Invalid private indexer list")
    resources = config.setdefault("resources", [])
    known_names = {
        item["match"].get("name")
        for item in resources
        if item.get("endpoint") == "indexer"
    }
    known_tags = {
        item["match"].get("label")
        for item in resources
        if item.get("endpoint") == "tag"
    }
    private_resources = []
    for item in indexers:
        if (
            not isinstance(item, dict)
            or not set(item).issubset({
                "name",
                "implementation",
                "enable",
                "priority",
                "appProfile",
                "tags",
                "fields",
            })
            or not {"name", "implementation", "tags", "fields"}.issubset(item)
        ):
            raise ConfigurationError("Invalid private indexer entry")
        name = item["name"]
        tags = item["tags"]
        invalid_identity = (
            not isinstance(name, str)
            or not name.strip()
            or name in known_names
            or not isinstance(item["implementation"], str)
            or not item["implementation"].strip()
        )
        invalid_settings = (
            type(item.get("enable", True)) is not bool
            or type(item.get("priority", 25)) is not int
            or not 1 <= item.get("priority", 25) <= 50
            or not isinstance(item.get("appProfile", "Standard"), str)
            or not isinstance(item["fields"], dict)
        )
        invalid_route = (
            not isinstance(tags, list)
            or not all(isinstance(tag, str) and tag for tag in tags)
            or len(set(tags)) != len(tags)
            or ("vpn" in tags) == ("direct" in tags)
            or ("browser-challenge" in tags and "vpn" not in tags)
        )
        if invalid_identity or invalid_settings or invalid_route:
            raise ConfigurationError("Invalid private indexer fields or route")
        known_names.add(name)
        for tag in tags:
            if tag not in known_tags:
                resources.append({
                    "endpoint": "tag",
                    "match": {"label": tag},
                    "values": {},
                })
                known_tags.add(tag)
        private_resources.append({
            "endpoint": "indexer",
            "match": {"name": name},
            "values": {
                "implementation": item["implementation"],
                "enable": item.get("enable", True),
                "priority": item.get("priority", 25),
                "appProfileId": {
                    "_lookup": {
                        "endpoint": "appprofile",
                        "name": item.get("appProfile", "Standard"),
                    }
                },
                "tags": [{"_lookup": {"endpoint": "tag", "name": tag}} for tag in tags],
                "fields": item["fields"],
            },
        })
    resources.extend(private_resources)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        raw = json.loads(args.configuration.read_text())
        validate_url(raw["url"])
        config = resolve(raw)
        if config.get("mode") not in {"managed", "bootstrap"}:
            raise ConfigurationError("Unknown reconciliation mode")
        private_indexers = add_private_indexers(config)
        client = Client(config["url"], {"X-Api-Key": config["apiKey"]})
        readiness = {
            "sonarr": "/api/v3/system/status",
            "radarr": "/api/v3/system/status",
            "lidarr": "/api/v1/system/status",
            "prowlarr": "/api/v1/system/status",
            "jellyfin": "/health",
            "seerr": "/api/v1/status",
            "bazarr": "/api/system/status",
            "navidrome": "/ping",
            "audiobookshelf": "/status",
            "autobrr": "/api/healthz/readiness",
        }
        if config["kind"] not in readiness:
            raise ConfigurationError("Unsupported application")
        client.wait_ready(
            readiness[config["kind"]],
            json_response=config["kind"] not in {"navidrome", "jellyfin", "autobrr"},
            expected_body=b"Healthy" if config["kind"] == "jellyfin" else None,
        )
        if config["kind"] in {"sonarr", "radarr", "lidarr", "prowlarr"}:
            result = reconcile_arr(client, config, args.dry_run)
        elif config["kind"] == "autobrr":
            from autobrr import reconcile as reconcile_autobrr

            result = reconcile_autobrr(client, config, args.dry_run)
        elif config["kind"] == "audiobookshelf":
            result = reconcile_audiobookshelf(client, config, args.dry_run)
        elif config["kind"] == "navidrome":
            result = reconcile_navidrome(client, config, args.dry_run)
        elif config["kind"] == "bazarr":
            result = reconcile_bazarr(client, config, args.dry_run)
        elif config["kind"] == "seerr":
            result = reconcile_seerr(client, config, args.dry_run)
        elif config["kind"] == "jellyfin":
            result = reconcile_jellyfin(client, config, args.dry_run)
        else:
            raise ConfigurationError("Unsupported application")
        if private_indexers and "plannedDependencies" in result:
            result["plannedDependencyCount"] = len(result.pop("plannedDependencies"))
        print(json.dumps({"dryRun": args.dry_run, **result}, sort_keys=True))
    except APIUnavailableError as error:
        print(str(error), file=sys.stderr)
        return 75  # EX_TEMPFAIL: systemd schedules another attempt.
    except ConfigurationError as error:
        print(str(error), file=sys.stderr)
        return 65  # EX_DATAERR: retrying cannot repair configuration.
    except OSError, ValueError, KeyError, TypeError:
        # Do not emit tracebacks or API objects that may include secret values.
        print("Invalid configuration, credentials or API response", file=sys.stderr)
        return 65
    return 0


if __name__ == "__main__":
    sys.exit(main())
