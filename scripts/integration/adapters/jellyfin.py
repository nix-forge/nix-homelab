"""Reconcile Jellyfin bootstrap, libraries and accounts."""

import json
import os
import urllib.parse
from pathlib import Path

from common import ConfigurationError, merge, password_fingerprint

RECOVERABLE_ERRORS = (ConfigurationError, KeyError, TypeError, ValueError)


def add_library_path(client, name, path):
    client.request(
        "POST",
        "/Library/VirtualFolders/Paths?refreshLibrary=false",
        {"Name": name, "PathInfo": {"Path": path}},
    )


def remove_library_path(client, name, path):
    query = urllib.parse.urlencode({
        "name": name,
        "path": path,
        "refreshLibrary": "false",
    })
    client.request("DELETE", "/Library/VirtualFolders/Paths?" + query)


def rollback_library_paths(client, name, added, removed):
    failed = False
    for path in removed:
        try:
            add_library_path(client, name, path)
        except RECOVERABLE_ERRORS:
            failed = True
    for path in reversed(added):
        try:
            remove_library_path(client, name, path)
        except RECOVERABLE_ERRORS:
            failed = True
    return failed


def update_library_paths(client, name, changes):
    item_id = changes["item_id"]
    additions = changes["additions"]
    removals = changes["removals"]
    options = changes["options"]
    added = []
    removed = []
    try:
        for path in additions:
            add_library_path(client, name, path)
            added.append(path)
        for path in removals:
            remove_library_path(client, name, path)
            removed.append(path)
        client.request(
            "POST",
            "/Library/VirtualFolders/LibraryOptions",
            {"Id": item_id, "LibraryOptions": options},
        )
    except RECOVERABLE_ERRORS as error:
        if rollback_library_paths(client, name, added, removed):
            raise ConfigurationError(
                "Jellyfin library update failed and could not be rolled back"
            ) from error
        raise


def reconcile_jellyfin(client, config, dry_run):
    settings = config.get("settings", {})
    login = settings.get("login", {})
    info = client.request("GET", "/System/Info/Public")
    if not info.get("StartupWizardCompleted"):
        if not login.get("username") or not login.get("password"):
            raise ConfigurationError(
                "Initial Jellyfin setup requires administrator login credentials"
            )
        if dry_run:
            return {"bootstrapRequired": True}
        client.request(
            "POST",
            "/Startup/Configuration",
            settings.get(
                "startup",
                {
                    "ServerName": "Media library",
                    "UICulture": "en",
                    "MetadataCountryCode": "US",
                    "PreferredMetadataLanguage": "en",
                },
            ),
        )
        client.request("GET", "/Startup/User")
        client.request(
            "POST",
            "/Startup/User",
            {"Name": login["username"], "Password": login["password"]},
        )
        client.request(
            "POST",
            "/Startup/RemoteAccess",
            {"EnableRemoteAccess": False, "EnableAutomaticPortMapping": False},
        )
        client.request("POST", "/Startup/Complete")
    client.headers = {
        "Authorization": 'MediaBrowser Client="nix-homelab", Device="configuration", DeviceId="nix-homelab-integration", Version="1"'
    }
    if config.get("apiKey"):
        token = config["apiKey"]
    else:
        token = client.request(
            "POST",
            "/Users/AuthenticateByName",
            {"Username": login["username"], "Pw": login["password"]},
        )["AccessToken"]
    client.headers["Authorization"] += ", Token=" + json.dumps(token)
    changed = 0
    if "encoding" in settings and (
        config["mode"] == "managed" or not info.get("StartupWizardCompleted")
    ):
        current_encoding = client.request("GET", "/System/Configuration/encoding")
        if not set(settings["encoding"]).issubset(current_encoding):
            raise ConfigurationError("Unknown Jellyfin encoding option")
        desired_encoding = merge(current_encoding, settings["encoding"])
        if desired_encoding != current_encoding:
            changed += 1
            if not dry_run:
                client.request(
                    "POST", "/System/Configuration/encoding", desired_encoding
                )
    if "network" in settings and (
        config["mode"] == "managed" or not info.get("StartupWizardCompleted")
    ):
        current_network = client.request("GET", "/System/Configuration/network")
        if not set(settings["network"]).issubset(current_network):
            raise ConfigurationError("Unknown Jellyfin network option")
        desired_network = merge(current_network, settings["network"])
        if desired_network != current_network:
            changed += 1
            if not dry_run:
                client.request("POST", "/System/Configuration/network", desired_network)
    if "branding" in settings and (
        config["mode"] == "managed" or not info.get("StartupWizardCompleted")
    ):
        current_branding = client.request("GET", "/System/Configuration/branding")
        if not set(settings["branding"]).issubset(current_branding):
            raise ConfigurationError("Unknown Jellyfin branding option")
        desired_branding = merge(current_branding, settings["branding"])
        if desired_branding != current_branding:
            changed += 1
            if not dry_run:
                client.request(
                    "POST", "/System/Configuration/branding", desired_branding
                )
    libraries = client.request("GET", "/Library/VirtualFolders")
    library_paths_changed = False
    for name, spec in settings.get("libraries", {}).items():
        matches = [item for item in libraries if item["Name"] == name]
        if len(matches) > 1:
            raise ConfigurationError("Ambiguous library identity")
        current = matches[0] if matches else None
        if current and config["mode"] == "bootstrap":
            continue
        declared = {
            **spec.get("options", {}),
            "PathInfos": [{"Path": path} for path in spec["paths"]],
        }
        if not current:
            changed += 1
            if not dry_run:
                query = urllib.parse.urlencode({
                    "name": name,
                    "collectionType": spec["collectionType"],
                    "refreshLibrary": "false",
                })
                client.request(
                    "POST",
                    "/Library/VirtualFolders?" + query,
                    {"LibraryOptions": declared},
                )
                library_paths_changed = True
        else:
            options = merge(current.get("LibraryOptions", {}), declared)
            # Locations are the actual media shortcuts. Updating PathInfos alone
            # does not remove old shortcuts in Jellyfin's LibraryOptions API.
            locations = current["Locations"]
            additions = [path for path in spec["paths"] if path not in locations]
            removals = [path for path in locations if path not in spec["paths"]]
            if additions or removals or options != current.get("LibraryOptions", {}):
                changed += 1
                if not dry_run:
                    update_library_paths(
                        client,
                        name,
                        {
                            "item_id": current["ItemId"],
                            "additions": additions,
                            "removals": removals,
                            "options": options,
                        },
                    )
                    library_paths_changed |= bool(additions or removals)
    # Path mutations skip per-request scans to avoid scanning midway through
    # reconciliation. Start one scan after all library paths are stable.
    if library_paths_changed:
        client.request("POST", "/Library/Refresh")
    users = client.request("GET", "/Users")
    state_path = Path(os.environ.get("STATE_DIRECTORY", ".")) / "password-state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    managed_names = [
        spec.get("name", key) for key, spec in settings.get("users", {}).items()
    ]
    if any(not isinstance(name, str) or not name for name in managed_names) or len(
        set(managed_names)
    ) != len(managed_names):
        raise ConfigurationError("Invalid or duplicate managed Jellyfin user identity")
    for key, spec in settings.get("users", {}).items():
        name = spec.get("name", key)
        if name == login.get("username") and key != name:
            raise ConfigurationError(
                "Managed Jellyfin user collides with administrator identity"
            )
        matches = [user for user in users if user["Name"] == name]
        if len(matches) > 1:
            raise ConfigurationError("Ambiguous user identity")
        current = matches[0] if matches else None
        if current and config["mode"] == "bootstrap":
            continue
        if not current:
            changed += 1
            if dry_run:
                continue
            if not spec.get("password"):
                raise ConfigurationError(
                    "New accounts require a nonempty runtime password"
                )
            current = client.request(
                "POST", "/Users/New", {"Name": name, "Password": spec["password"]}
            )
        policy = merge(current.get("Policy", {}), spec.get("policy", {}))
        if "IsAdministrator" not in spec.get("policy", {}):
            policy["IsAdministrator"] = False
        if policy != current.get("Policy", {}):
            changed += 1
            if not dry_run:
                client.request("POST", "/Users/" + current["Id"] + "/Policy", policy)
        if spec.get("password"):
            digest = password_fingerprint(spec["password"], state.get(current["Id"]))
            if state.get(current["Id"]) != digest:
                changed += 1
                if not dry_run:
                    body = {"NewPw": spec["password"]}
                    if name == login.get("username") and not config.get("apiKey"):
                        body["CurrentPw"] = login["password"]
                    client.request(
                        "POST", "/Users/" + current["Id"] + "/Password", body
                    )
                    state[current["Id"]] = digest
                    state_path.parent.mkdir(parents=True, exist_ok=True)
                    temporary = state_path.with_suffix(".tmp")
                    with open(
                        temporary,
                        "w",
                        encoding="utf-8",
                        opener=lambda path, flags: os.open(path, flags, 0o600),
                    ) as handle:
                        json.dump(state, handle)
                    temporary.replace(state_path)
    playback = settings.get("playback", {})
    if playback:
        for user in client.request("GET", "/Users"):
            current_config = user.get("Configuration", {})
            desired_config = merge(current_config, playback)
            if desired_config != current_config:
                changed += 1
                if not dry_run:
                    client.request(
                        "POST",
                        "/Users/" + user["Id"] + "/Configuration",
                        desired_config,
                    )
    return {"changed": changed}
