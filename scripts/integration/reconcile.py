"""Reconcile declared application objects without deleting unowned state.

The public interface is a JSON configuration and runtime systemd credentials.
Only bounded HTTP requests are made. Responses and credentials are never logged.
"""

import argparse
import copy
import hashlib
import hmac
import http.cookiejar
import ipaddress
import json
import os
import re
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class ConfigurationError(Exception):
    pass


class APIError(ConfigurationError):
    def __init__(self, status):
        self.status = status
        super().__init__(f"API request failed with HTTP {status}")


class APIUnavailable(ConfigurationError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        raise ConfigurationError("API redirects are forbidden")


def validate_url(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ConfigurationError("API URL must not contain credentials, query or fragment")
    try:
        loopback = ipaddress.ip_address(parsed.hostname).is_loopback
    except ValueError:
        loopback = parsed.hostname == "localhost"
    if not parsed.hostname or parsed.scheme not in ("http", "https"):
        raise ConfigurationError("Invalid API URL")
    if parsed.scheme != "https" and not loopback:
        raise ConfigurationError("Non-loopback API endpoints require HTTPS")
    return url.rstrip("/")


def resolve(value):
    if isinstance(value, dict):
        if "_credential" in value:
            name = value["_credential"]
            if set(value) != {"_credential"} or not re.fullmatch(r"[A-Za-z0-9_-]+", name):
                raise ConfigurationError("Invalid credential reference")
            directory = Path(os.environ["CREDENTIALS_DIRECTORY"])
            result = (directory / name).read_text().rstrip("\r\n")
            if not result:
                raise ConfigurationError("Empty credential")
            return result
        return {key: resolve(item) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item) for item in value]
    return value


class Client:
    def __init__(self, url, headers=None):
        self.url = validate_url(url)
        self.headers = headers or {}
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            NoRedirect(),
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
        )

    def request(self, method, path, body=None, form=False, json_response=True, read_only=None):
        if not path.startswith("/") or path.startswith("//") or ".." in path:
            raise ConfigurationError("Invalid API path")
        payload = (
            None
            if body is None
            else (
                urllib.parse.urlencode(body, doseq=True).encode()
                if form
                else json.dumps(body).encode()
            )
        )
        content_type = "application/x-www-form-urlencoded" if form else "application/json"
        request = urllib.request.Request(
            self.url + path,
            data=payload,
            method=method,
            headers={"Content-Type": content_type, **self.headers},
        )
        # Some upstream APIs mutate state through GET endpoints.
        read_only = method == "GET" if read_only is None else read_only
        for attempt in range(4 if read_only else 1):
            try:
                with self.opener.open(request, timeout=15) as response:
                    data = response.read(8 * 1024 * 1024 + 1)
                    if len(data) > 8 * 1024 * 1024:
                        raise ConfigurationError("API response exceeded size limit")
                    return (json.loads(data) if data else None) if json_response else data
            except urllib.error.HTTPError as error:
                if read_only and error.code in (429, 502, 503, 504) and attempt < 3:
                    time.sleep(2**attempt)
                    continue
                if error.code in (429, 502, 503, 504):
                    raise APIUnavailable("API is not ready") from None
                raise APIError(error.code) from None
            except (urllib.error.URLError, TimeoutError):
                if read_only and attempt < 3:
                    time.sleep(2**attempt)
                    continue
                raise APIUnavailable("API unavailable or request timed out") from None
        raise ConfigurationError("API retry limit exceeded")

    def wait_ready(self, path, json_response=True, expected_body=None):
        deadline = time.monotonic() + 90
        while True:
            try:
                result = self.request("GET", path, json_response=json_response)
                if expected_body is not None and result.strip() != expected_body:
                    raise APIUnavailable("API has not completed initialization")
                return
            except APIUnavailable:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(2)


def merge(current, values):
    result = copy.deepcopy(current)
    for key, value in values.items():
        if key == "fields" and isinstance(value, dict):
            fields = {field["name"]: field for field in result.get("fields", [])}
            if not set(value).issubset(fields):
                raise ConfigurationError("Unknown provider schema field")
            for name, field_value in value.items():
                fields[name]["value"] = field_value
        elif isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def resolve_arr_lookups(client, prefix, value):
    if isinstance(value, dict):
        if "_lookup" in value:
            spec = value["_lookup"]
            if set(value) != {"_lookup"} or set(spec) != {"endpoint", "name"}:
                raise ConfigurationError("Invalid named resource lookup")
            if spec["endpoint"] not in {"qualityprofile", "metadataprofile", "tag"}:
                raise ConfigurationError("Unsupported named resource lookup")
            candidates = client.request("GET", prefix + spec["endpoint"])
            key = "label" if spec["endpoint"] == "tag" else "name"
            matches = [item for item in candidates if item.get(key) == spec["name"]]
            if len(matches) != 1:
                raise ConfigurationError("Named resource is missing or ambiguous")
            return matches[0]["id"]
        return {key: resolve_arr_lookups(client, prefix, item) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve_arr_lookups(client, prefix, item) for item in value]
    return value


def reconcile_arr(client, config, dry_run):
    version = "v1" if config["kind"] in ("lidarr", "prowlarr") else "v3"
    prefix = f"/api/{version}/"
    counts = {"created": 0, "updated": 0, "unchanged": 0}
    allowed = {
        "rootfolder",
        "downloadclient",
        "indexer",
        "applications",
        "tag",
        "qualityprofile",
        "delayprofile",
        "notification",
        "remotepathmapping",
    }
    settings = config.get("settings", {})
    policies = {
        "downloadHandling": (
            "downloadclient",
            {
                "enableCompletedDownloadHandling",
                "autoRedownloadFailed",
                "autoRedownloadFailedFromInteractiveSearch",
            },
        ),
        "mediaManagement": ("mediamanagement", {"copyUsingHardlinks"}),
    }
    if set(settings) - policies.keys():
        raise ConfigurationError("Unsupported manager settings section")
    for section, (endpoint, fields) in policies.items():
        declared = settings.get(section, {})
        if not declared:
            continue
        if (
            config["kind"] == "prowlarr"
            or set(declared) - fields
            or any(not isinstance(value, bool) for value in declared.values())
        ):
            raise ConfigurationError("Unsupported manager import policy")
        endpoint = prefix + "config/" + endpoint
        current = client.request("GET", endpoint)
        if not isinstance(current, dict) or set(declared) - current.keys():
            raise ConfigurationError("Manager does not expose declared import settings")
        desired = merge(current, declared)
        if config["mode"] == "bootstrap" or desired == current:
            counts["unchanged"] += 1
        else:
            counts["updated"] += 1
            if not dry_run:
                client.request("PUT", endpoint, desired)
    for resource in config.get("resources", []):
        endpoint = resource["endpoint"]
        if endpoint not in allowed:
            raise ConfigurationError("Unsupported resource endpoint")
        match = resource["match"]
        if not match or not set(match).issubset({"name", "path", "label"}):
            raise ConfigurationError("A stable name, path or label is required")
        values = resolve_arr_lookups(client, prefix, merge(resource.get("values", {}), match))
        objects = client.request("GET", prefix + endpoint)
        candidates = [obj for obj in objects if all(obj.get(k) == v for k, v in match.items())]
        if len(candidates) > 1:
            raise ConfigurationError("Ambiguous resource identity")
        current = candidates[0] if candidates else None
        if current and config["mode"] == "bootstrap":
            counts["unchanged"] += 1
            continue
        if (
            current
            and "implementation" in values
            and current.get("implementation") != values["implementation"]
        ):
            raise ConfigurationError("Existing provider implementation cannot be replaced")
        template = current or {}
        if not current and "implementation" in values:
            schemas = client.request("GET", prefix + endpoint + "/schema")
            candidates = [
                schema
                for schema in schemas
                if schema.get("implementation") == values["implementation"]
            ]
            if len(candidates) != 1:
                raise ConfigurationError("Provider schema is missing or ambiguous")
            template = candidates[0]
        desired = merge(template, values)
        if current == desired:
            counts["unchanged"] += 1
        elif current:
            counts["updated"] += 1
            if not dry_run:
                client.request("PUT", prefix + endpoint + "/" + str(current["id"]), desired)
        else:
            counts["created"] += 1
            desired.pop("id", None)
            if not dry_run:
                client.request("POST", prefix + endpoint, desired)
    return counts


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
                client.request("POST", "/System/Configuration/encoding", desired_encoding)
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
                query = urllib.parse.urlencode(
                    {
                        "name": name,
                        "collectionType": spec["collectionType"],
                        "refreshLibrary": "false",
                    }
                )
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
                    # Establish every new location before detaching old ones. A
                    # failed addition must leave the existing library accessible.
                    for path in additions:
                        client.request(
                            "POST",
                            "/Library/VirtualFolders/Paths?refreshLibrary=false",
                            {"Name": name, "PathInfo": {"Path": path}},
                        )
                    for path in removals:
                        query = urllib.parse.urlencode(
                            {"name": name, "path": path, "refreshLibrary": "false"}
                        )
                        client.request("DELETE", "/Library/VirtualFolders/Paths?" + query)
                    client.request(
                        "POST",
                        "/Library/VirtualFolders/LibraryOptions",
                        {"Id": current["ItemId"], "LibraryOptions": options},
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
                raise ConfigurationError("New accounts require a nonempty runtime password")
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
                    if name == login.get("username"):
                        body["CurrentPw"] = login["password"]
                    client.request("POST", "/Users/" + current["Id"] + "/Password", body)
                    state[current["Id"]] = digest
                    state_path.parent.mkdir(parents=True, exist_ok=True)
                    temporary = state_path.with_suffix(".tmp")
                    with open(
                        temporary,
                        "w",
                        opener=lambda path, flags: os.open(path, flags, 0o600),
                    ) as handle:
                        json.dump(state, handle)
                    temporary.replace(state_path)
    return {"changed": changed}


def reconcile_seerr(client, config, dry_run):
    settings = config.get("settings", {})
    public = client.request("GET", "/api/v1/settings/public")
    initialized = public.get("initialized", False)
    if not initialized and dry_run:
        return {"bootstrapRequired": True}
    if not initialized or not config.get("apiKey"):
        login = settings.get("login")
        if not login:
            raise ConfigurationError("Seerr onboarding requires Jellyfin login configuration")
        if not initialized and public.get("mediaServerType") != 2:
            login = {"urlBase": "", "useSsl": False, "port": 8096, "serverType": 2, **login}
        if initialized or public.get("mediaServerType") == 2:
            login = {
                key: value
                for key, value in login.items()
                if key not in ("hostname", "port", "useSsl", "urlBase", "serverType")
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
                + ("&enable=" + urllib.parse.quote(",".join(sorted(enabled))) if enabled else ""),
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
            tested = client.request("POST", "/api/v1/settings/" + kind + "/test", connection)
            profiles = [
                profile
                for profile in tested["profiles"]
                if profile["name"] == spec["activeProfileName"]
            ]
            if len(profiles) != 1:
                raise ConfigurationError("Selected quality profile is missing or ambiguous")
            if spec["activeDirectory"] not in [folder["path"] for folder in tested["rootFolders"]]:
                raise ConfigurationError("Selected library root is not registered with the manager")
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


def reconcile_bazarr(client, config, dry_run):
    current = client.request("GET", "/api/system/settings")
    if config["mode"] == "bootstrap":
        return {"unchanged": True}
    changed = {}
    settings = config.get("settings", {})
    for section, fields in settings.items():
        if section in {"languageProfiles", "enabledLanguages", "defaultProfiles"}:
            continue
        if section not in current or not isinstance(fields, dict):
            raise ConfigurationError("Unknown subtitle settings section")
        for key, value in fields.items():
            if key not in current[section]:
                raise ConfigurationError("Unknown subtitle setting")
            if current[section][key] != value:
                if isinstance(value, bool):
                    value = str(value).lower()
                changed[f"settings-{section}-{key}"] = value
    if settings.get("languageProfiles") or settings.get("defaultProfiles"):
        profiles = client.request("GET", "/api/system/languages/profiles")
        desired = copy.deepcopy(profiles)
        next_id = max((item["profileId"] for item in profiles), default=0) + 1
        for name, fields in settings.get("languageProfiles", {}).items():
            allowed = {"items", "cutoff", "mustContain", "mustNotContain", "originalFormat", "tag"}
            if not set(fields).issubset(allowed):
                raise ConfigurationError("Unknown subtitle language profile field")
            matches = [item for item in desired if item["name"] == name]
            if len(matches) > 1:
                raise ConfigurationError("Ambiguous subtitle language profile")
            if matches:
                matches[0].update(fields)
            else:
                if not fields.get("items"):
                    raise ConfigurationError("New subtitle profiles require languages")
                desired.append(
                    {
                        "profileId": next_id,
                        "name": name,
                        "cutoff": None,
                        "mustContain": "",
                        "mustNotContain": "",
                        "originalFormat": False,
                        "tag": None,
                        **fields,
                    }
                )
                next_id += 1
        if desired != profiles:
            # Bazarr replaces this collection. Preserve every undeclared profile.
            changed["languages-profiles"] = json.dumps(desired)
        for kind, name in settings.get("defaultProfiles", {}).items():
            if kind not in {"series", "movies"}:
                raise ConfigurationError("Unknown subtitle default profile target")
            matches = [item for item in desired if item["name"] == name]
            if len(matches) != 1:
                raise ConfigurationError("Subtitle default profile is missing or ambiguous")
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
    return {"changed": len(changed)}


def reconcile_navidrome(client, config, dry_run):
    settings = config["settings"]
    login = settings["login"]
    declared_users = settings.get("users", {})
    names = [name.casefold() for name in declared_users]
    if len(set(names)) != len(names):
        raise ConfigurationError("Audio account declarations have ambiguous names")
    if login["username"].casefold() in names:
        raise ConfigurationError(
            "Manage the integration administrator through an attended account change"
        )
    try:
        token = client.request("POST", "/auth/login", login)["token"]
    except APIError as error:
        if error.status != 401:
            raise
        if dry_run:
            return {"bootstrapRequired": True}
        # The server independently rejects this operation if any user exists.
        token = client.request("POST", "/auth/createAdmin", login)["token"]
    client.headers = {"X-ND-Authorization": "Bearer " + token}
    users = client.request("GET", "/api/user")
    state_path = Path(os.environ["STATE_DIRECTORY"]) / "audio-password-state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    changed = 0
    for name, spec in declared_users.items():
        matches = [user for user in users if user["userName"].casefold() == name.casefold()]
        if len(matches) > 1:
            raise ConfigurationError("Ambiguous audio account")
        current = matches[0] if matches else None
        if current and config["mode"] == "bootstrap":
            continue
        declared = {key: value for key, value in spec.items() if key != "password"}
        declared.update(
            {
                "userName": current["userName"] if current else name,
                "isAdmin": spec.get("isAdmin", False),
            }
        )
        if not current and not spec.get("password"):
            raise ConfigurationError("New accounts require a nonempty runtime password")
        desired = merge(current or {}, declared)
        digest = (
            password_fingerprint(spec["password"], state.get(current["id"]) if current else None)
            if spec.get("password")
            else None
        )
        if digest and (not current or state.get(current["id"]) != digest):
            desired["password"] = spec["password"]
        if desired != current:
            changed += 1
            if not dry_run:
                result = client.request(
                    "PUT" if current else "POST",
                    "/api/user" + ("/" + current["id"] if current else ""),
                    desired,
                )
                if digest:
                    state[result["id"]] = digest
                    state_path.parent.mkdir(parents=True, exist_ok=True)
                    temporary = state_path.with_suffix(".tmp")
                    with open(
                        temporary, "w", opener=lambda path, flags: os.open(path, flags, 0o600)
                    ) as handle:
                        json.dump(state, handle)
                    temporary.replace(state_path)
    return {"changed": changed}


def password_fingerprint(password, previous=None):
    # Change detection must not introduce a cheap unsalted password verifier.
    if isinstance(previous, str) and previous.startswith("scrypt$"):
        _, salt_hex, digest_hex = previous.split("$")
        salt = bytes.fromhex(salt_hex)
        digest = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1).hex()
        if hmac.compare_digest(digest, digest_hex):
            return previous
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1).hex()
    return "scrypt$" + salt.hex() + "$" + digest


def contains(current, declared):
    if isinstance(declared, dict):
        return isinstance(current, dict) and all(
            key in current and contains(current[key], value) for key, value in declared.items()
        )
    if isinstance(declared, list):
        return (
            isinstance(current, list)
            and len(current) == len(declared)
            and all(contains(a, b) for a, b in zip(current, declared, strict=True))
        )
    return current == declared


def reconcile_audiobookshelf(client, config, dry_run):
    settings = config["settings"]
    status = client.request("GET", "/status")
    if not status["isInit"]:
        if dry_run:
            return {"bootstrapRequired": True}
        login = settings["login"]
        if not login.get("password"):
            raise ConfigurationError("Initial audiobook administrator requires a password")
        client.request("POST", "/init", {"newRoot": login}, json_response=False)
    if config.get("apiKey"):
        token = config["apiKey"]
    else:
        user = client.request("POST", "/login", settings["login"])["user"]
        token = user.get("accessToken") or user["token"]
    client.headers = {"Authorization": "Bearer " + token}
    changed = 0
    libraries = client.request("GET", "/api/libraries")["libraries"]
    for name, spec in settings.get("libraries", {}).items():
        matches = [item for item in libraries if item["name"] == name]
        if len(matches) > 1:
            raise ConfigurationError("Ambiguous audiobook library")
        current = matches[0] if matches else None
        if current and config["mode"] == "bootstrap":
            continue
        declared = {**spec, "name": name}
        if not current or not contains(current, declared):
            changed += 1
            if not dry_run:
                client.request(
                    "PATCH" if current else "POST",
                    "/api/libraries" + ("/" + current["id"] if current else ""),
                    declared,
                )
    users = client.request("GET", "/api/users")["users"]
    state_path = Path(os.environ["STATE_DIRECTORY"]) / "audio-password-state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    for name, spec in settings.get("users", {}).items():
        matches = [user for user in users if user["username"] == name]
        if len(matches) > 1:
            raise ConfigurationError("Ambiguous audiobook account")
        current = matches[0] if matches else None
        if current and config["mode"] == "bootstrap":
            continue
        declared = {key: value for key, value in spec.items() if key != "password"}
        declared.update(
            {
                "username": name,
                "type": spec.get("type", "user"),
                "isActive": spec.get("isActive", True),
            }
        )
        digest = (
            password_fingerprint(spec["password"], state.get(current["id"]) if current else None)
            if spec.get("password")
            else None
        )
        if not current and not digest:
            raise ConfigurationError("New accounts require a nonempty runtime password")
        if digest and (not current or state.get(current["id"]) != digest):
            declared["password"] = spec["password"]
        if not current or not contains(current, declared):
            changed += 1
            if not dry_run:
                result = client.request(
                    "PATCH" if current else "POST",
                    "/api/users" + ("/" + current["id"] if current else ""),
                    declared,
                )["user"]
                if digest:
                    state[result["id"]] = digest
                    state_path.parent.mkdir(parents=True, exist_ok=True)
                    temporary = state_path.with_suffix(".tmp")
                    with open(
                        temporary, "w", opener=lambda path, flags: os.open(path, flags, 0o600)
                    ) as handle:
                        json.dump(state, handle)
                    temporary.replace(state_path)
    return {"changed": changed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        raw = json.loads(args.configuration.read_text())
        validate_url(raw["url"])
        config = resolve(raw)
        if config.get("mode") not in ("managed", "bootstrap"):
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
            json_response=config["kind"] not in ("navidrome", "jellyfin", "autobrr"),
            expected_body=b"Healthy" if config["kind"] == "jellyfin" else None,
        )
        if config["kind"] in ("sonarr", "radarr", "lidarr", "prowlarr"):
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
    except (OSError, ValueError, KeyError, TypeError):
        # Do not emit tracebacks or API objects that may include secret values.
        print("Invalid configuration, credentials or API response", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
