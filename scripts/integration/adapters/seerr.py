"""Reconcile Seerr onboarding, libraries and manager destinations."""

import time
import urllib.parse

from common import ConfigurationError, merge

AUTO_APPROVE_MASK = 128 | 256 | 512 | 32768 | 65536 | 131072
REQUEST = 32


def reconcile_auto_approve_users(client, approved_usernames, dry_run):
    if (
        not isinstance(approved_usernames, list)
        or any(not isinstance(name, str) or not name for name in approved_usernames)
        or len(approved_usernames) != len(set(approved_usernames))
    ):
        raise ConfigurationError("Invalid Seerr auto-approval allowlist")

    users = []
    page = 0
    while True:
        response = client.request("GET", f"/api/v1/user?take=100&skip={page * 100}")
        users.extend(response["results"])
        page += 1
        if page >= response["pageInfo"]["pages"]:
            break
        if page >= 100:
            raise ConfigurationError("Seerr user list exceeds the managed limit")

    by_name = {}
    for user in users:
        name = user.get("jellyfinUsername")
        if name not in approved_usernames:
            continue
        if name in by_name:
            raise ConfigurationError(
                "Ambiguous Seerr username in auto-approval allowlist"
            )
        by_name[name] = user
    missing = set(approved_usernames) - by_name.keys()
    if missing:
        raise ConfigurationError("An approved Seerr account is missing")

    updates = []
    for user in users:
        current = user["permissions"]
        if not isinstance(current, int) or current < 0:
            raise ConfigurationError("Invalid Seerr user permissions")
        if user.get("jellyfinUsername") in approved_usernames:
            # ADMIN already auto-approves, and Seerr forbids editing one's own
            # permissions through the API used by the reconciliation login.
            desired = current if current & 2 else current | REQUEST | 128
        else:
            if current & 2:
                raise ConfigurationError(
                    "Unlisted Seerr administrator can auto-approve"
                )
            desired = current & ~AUTO_APPROVE_MASK
        if desired != current:
            updates.append((user["id"], desired))
    if not dry_run:
        for user_id, permissions in updates:
            client.request(
                "POST",
                f"/api/v1/user/{user_id}/settings/permissions",
                {"permissions": permissions},
            )
    return len(updates)


def reconcile_seerr(client, config, dry_run):
    settings = config.get("settings", {})
    public = client.request("GET", "/api/v1/settings/public")
    initialized = public.get("initialized", False)
    if not initialized and dry_run:
        return {"bootstrapRequired": True}
    if not initialized or not config.get("apiKey"):
        login = settings.get("login")
        if not login:
            raise ConfigurationError(
                "Seerr onboarding requires Jellyfin login configuration"
            )
        if not initialized and public.get("mediaServerType") != 2:
            login = {
                "urlBase": "",
                "useSsl": False,
                "port": 8096,
                "serverType": 2,
                **login,
            }
        if initialized or public.get("mediaServerType") == 2:
            login = {
                key: value
                for key, value in login.items()
                if key not in {"hostname", "port", "useSsl", "urlBase", "serverType"}
            }
        client.request("POST", "/api/v1/auth/jellyfin", login)
    changed = 0
    if "libraries" in settings and (not initialized or config["mode"] == "managed"):
        libraries = client.request("GET", "/api/v1/settings/jellyfin")["libraries"]
        available = {item["name"] for item in libraries}
        if not set(settings["libraries"]).issubset(available):
            changed += 1
            if dry_run:
                return {"changed": changed, "librarySyncRequired": True}
            libraries = client.request("POST", "/api/v1/settings/jellyfin/library/sync")
        selected = [item for item in libraries if item["name"] in settings["libraries"]]
        if len(selected) != len(settings["libraries"]):
            raise ConfigurationError("Requested Seerr library is not available yet")
        disabled = [item for item in selected if not item.get("enabled")]
        if disabled:
            changed += 1
            if not dry_run:
                for item in disabled:
                    client.request(
                        "PUT",
                        "/api/v1/settings/jellyfin/library/"
                        + urllib.parse.quote(str(item["id"]), safe=""),
                        {"enabled": True},
                    )
    for kind in ("radarr", "sonarr"):
        if not settings.get(kind):
            continue
        existing = client.request("GET", "/api/v1/settings/" + kind)
        for name, spec in settings[kind].items():
            matches = [item for item in existing if item["name"] == name]
            if len(matches) > 1:
                raise ConfigurationError("Ambiguous request destination")
            current = matches[0] if matches else None
            if current and config["mode"] == "bootstrap":
                continue
            connection = {
                key: spec[key]
                for key in ("hostname", "port", "apiKey", "useSsl", "baseUrl")
                if key in spec
            }
            # A manager can briefly return its old profile list after
            # Recyclarr finishes creating a new profile.
            for attempt in range(3):
                tested = client.request(
                    "POST", "/api/v1/settings/" + kind + "/test", connection
                )
                profiles = [
                    profile
                    for profile in tested["profiles"]
                    if profile["name"] == spec["activeProfileName"]
                ]
                anime_profiles = (
                    [
                        profile
                        for profile in tested["profiles"]
                        if profile["name"] == spec.get("activeAnimeProfileName")
                    ]
                    if kind == "sonarr" and spec.get("activeAnimeProfileName")
                    else None
                )
                if (
                    profiles and (anime_profiles is None or anime_profiles)
                ) or attempt == 2:
                    break
                time.sleep(1)
            if len(profiles) != 1:
                raise ConfigurationError(
                    "Selected quality profile is missing or ambiguous"
                )
            roots = [folder["path"] for folder in tested["rootFolders"]]
            directories = [spec["activeDirectory"]]
            if kind == "sonarr" and spec.get("activeAnimeDirectory"):
                directories.append(spec["activeAnimeDirectory"])
            if any(directory not in roots for directory in directories):
                raise ConfigurationError(
                    "Selected library root is not registered with the manager"
                )
            values = {**spec, "name": name, "activeProfileId": profiles[0]["id"]}
            if anime_profiles is not None:
                if len(anime_profiles) != 1:
                    raise ConfigurationError(
                        "Selected anime profile is missing or ambiguous"
                    )
                values["activeAnimeProfileId"] = anime_profiles[0]["id"]
            desired = merge(current or {}, values)
            if desired != current:
                changed += 1
                if not dry_run:
                    suffix = "/" + str(current["id"]) if current else ""
                    client.request(
                        "PUT" if current else "POST",
                        "/api/v1/settings/" + kind + suffix,
                        {key: value for key, value in desired.items() if key != "id"},
                    )
    # Singleton settings do not have an absent state. Bootstrap applies them only
    # during initial onboarding; managed mode merges only explicitly declared keys.
    for section in ("jellyfin", "main", "network", "notifications"):
        if section in settings and (not initialized or config["mode"] == "managed"):
            current = client.request("GET", "/api/v1/settings/" + section)
            desired = merge(current, settings[section])
            if current != desired:
                changed += 1
                if not dry_run:
                    # Seerr merges writes with its stored settings. Posting the
                    # fetched object sends read-only fields such as main.apiKey,
                    # which its OpenAPI request validator rejects.
                    client.request(
                        "POST", "/api/v1/settings/" + section, settings[section]
                    )
    if "autoApproveUsers" in settings and config["mode"] == "managed":
        changed += reconcile_auto_approve_users(
            client, settings["autoApproveUsers"], dry_run
        )
    if not initialized:
        client.request("POST", "/api/v1/settings/initialize")
    return {"changed": changed}
