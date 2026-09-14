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
    libraries = client.request("GET", "/Library/VirtualFolders")
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
    users = client.request("GET", "/Users")
    state_path = Path(os.environ.get("STATE_DIRECTORY", ".")) / "password-state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    for name, spec in settings.get("users", {}).items():
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
    return {"changed": changed}
