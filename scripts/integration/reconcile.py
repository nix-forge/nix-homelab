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
from common import Client, ConfigurationError, resolve, validate_url


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
        print(json.dumps({"dryRun": args.dry_run, **result}, sort_keys=True))
    except ConfigurationError as error:
        print(str(error), file=sys.stderr)
        return 1
    except OSError, ValueError, KeyError, TypeError:
        # Do not emit tracebacks or API objects that may include secret values.
        print("Invalid configuration, credentials or API response", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
