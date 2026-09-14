"""Reconcile qBittorrent categories and tags through the v5 Web API."""

import argparse
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "integration"))

from common import APIError, Client, ConfigurationError


def read_api_key():
    directory = Path(os.environ["CREDENTIALS_DIRECTORY"])
    key = (directory / "api-key").read_text().rstrip("\r\n")
    if not re.fullmatch(r"qbt_[A-Za-z0-9]{28}", key):
        raise ConfigurationError("Invalid qBittorrent API key")
    return key


def version_tuple(raw):
    match = re.fullmatch(rb"(\d+)\.(\d+)\.(\d+)", raw.strip())
    if not match:
        raise ConfigurationError("Invalid qBittorrent Web API version")
    return tuple(int(part) for part in match.groups())


def validate(config):
    if config.get("mode") not in {"bootstrap", "managed"}:
        raise ConfigurationError("Unknown qBittorrent reconciliation mode")
    categories = config.get("categories", {})
    tags = config.get("tags", [])
    if not isinstance(categories, dict) or not isinstance(tags, list):
        raise ConfigurationError("Invalid qBittorrent resource declarations")
    if any(
        not isinstance(name, str)
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", name)
        or not isinstance(spec, dict)
        or set(spec) != {"savePath"}
        or not isinstance(spec["savePath"], str)
        or not spec["savePath"].startswith("/")
        for name, spec in categories.items()
    ):
        raise ConfigurationError("Invalid qBittorrent category declaration")
    if len(tags) != len(set(tags)) or any(
        not isinstance(tag, str) or not re.fullmatch(r"[A-Za-z0-9][^,\r\n]*", tag)
        for tag in tags
    ):
        raise ConfigurationError("Invalid qBittorrent tag declaration")


def reconcile(client, config, dry_run):
    validate(config)
    api_version = client.request(
        "GET", "/api/v2/app/webapiVersion", json_response=False
    )
    if version_tuple(api_version) < (2, 14, 1):
        raise ConfigurationError(
            "qBittorrent API-key reconciliation requires Web API 2.14.1 or newer"
        )

    counts = {"created": 0, "updated": 0, "unchanged": 0}
    categories = client.request("GET", "/api/v2/torrents/categories")
    if not isinstance(categories, dict):
        raise ConfigurationError("Invalid qBittorrent category response")
    for name, spec in config.get("categories", {}).items():
        current = categories.get(name)
        if current is None:
            counts["created"] += 1
            if not dry_run:
                client.request(
                    "POST",
                    "/api/v2/torrents/createCategory",
                    {"category": name, "savePath": spec["savePath"]},
                    form=True,
                    json_response=False,
                )
        elif (
            config["mode"] == "managed" and current.get("savePath") != spec["savePath"]
        ):
            counts["updated"] += 1
            if not dry_run:
                client.request(
                    "POST",
                    "/api/v2/torrents/editCategory",
                    {"category": name, "savePath": spec["savePath"]},
                    form=True,
                    json_response=False,
                )
        else:
            counts["unchanged"] += 1

    tags = client.request("GET", "/api/v2/torrents/tags")
    if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
        raise ConfigurationError("Invalid qBittorrent tag response")
    missing_tags = [tag for tag in config.get("tags", []) if tag not in tags]
    counts["created"] += len(missing_tags)
    counts["unchanged"] += len(config.get("tags", [])) - len(missing_tags)
    if missing_tags and not dry_run:
        client.request(
            "POST",
            "/api/v2/torrents/createTags",
            {"tags": ",".join(missing_tags)},
            form=True,
            json_response=False,
        )
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        config = json.loads(args.configuration.read_text())
        client = Client(config["url"], {"Authorization": "Bearer " + read_api_key()})
        result = reconcile(client, config, args.dry_run)
        sys.stdout.write(
            json.dumps({"dryRun": args.dry_run, **result}, sort_keys=True) + "\n"
        )
    except (ConfigurationError, APIError) as error:
        sys.stderr.write(str(error) + "\n")
        return 1
    except OSError, ValueError, KeyError, TypeError:
        sys.stderr.write("Invalid configuration, credential or API response\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
