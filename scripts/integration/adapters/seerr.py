"""Reconcile Seerr onboarding, libraries and manager destinations."""

import urllib.parse

from common import ConfigurationError, merge


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
        enabled = {str(item["id"]) for item in libraries if item.get("enabled")}
        available = {item["name"] for item in libraries}
        if not set(settings["libraries"]).issubset(available):
            changed += 1
            if dry_run:
                return {"changed": changed, "librarySyncRequired": True}
            libraries = client.request(
                "GET",
                "/api/v1/settings/jellyfin/library?sync=true"
                + (
                    "&enable=" + urllib.parse.quote(",".join(sorted(enabled)))
                    if enabled
                    else ""
                ),
                read_only=False,
            )
        selected = [item for item in libraries if item["name"] in settings["libraries"]]
        if len(selected) != len(settings["libraries"]):
            raise ConfigurationError("Requested Seerr library is not available yet")
        if any(not item.get("enabled") for item in selected):
            changed += 1
            enabled.update(str(item["id"]) for item in selected)
            if not dry_run:
                client.request(
                    "GET",
                    "/api/v1/settings/jellyfin/library?enable="
                    + urllib.parse.quote(",".join(sorted(enabled))),
                    read_only=False,
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
            tested = client.request(
                "POST", "/api/v1/settings/" + kind + "/test", connection
            )
            profiles = [
                profile
                for profile in tested["profiles"]
                if profile["name"] == spec["activeProfileName"]
            ]
            if len(profiles) != 1:
                raise ConfigurationError(
                    "Selected quality profile is missing or ambiguous"
                )
            if spec["activeDirectory"] not in [
                folder["path"] for folder in tested["rootFolders"]
            ]:
                raise ConfigurationError(
                    "Selected library root is not registered with the manager"
                )
            values = {**spec, "name": name, "activeProfileId": profiles[0]["id"]}
            desired = merge(current or {}, values)
            if desired != current:
                changed += 1
                if not dry_run:
                    suffix = "/" + str(current["id"]) if current else ""
                    client.request(
                        "PUT" if current else "POST",
                        "/api/v1/settings/" + kind + suffix,
                        desired,
                    )
    # Singleton settings do not have an absent state. Bootstrap applies them only
    # during initial onboarding; managed mode merges only explicitly declared keys.
    for section in ("main", "notifications"):
        if section in settings and (not initialized or config["mode"] == "managed"):
            current = client.request("GET", "/api/v1/settings/" + section)
            desired = merge(current, settings[section])
            if current != desired:
                changed += 1
                if not dry_run:
                    client.request("POST", "/api/v1/settings/" + section, desired)
    if not initialized:
        client.request("POST", "/api/v1/settings/initialize")
    return {"changed": changed}
