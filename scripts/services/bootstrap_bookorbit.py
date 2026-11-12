"""Claim BookOrbit and verify its sealed administrator before exposure."""

import http.cookiejar
import json
import logging
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import override

LOGGER = logging.getLogger(__name__)


def _credential(name: str) -> str:
    value = (Path(os.environ["CREDENTIALS_DIRECTORY"]) / name).read_text().strip()
    if not value or any(character in value for character in "\r\n\0"):
        message = f"Invalid {name} credential"
        raise RuntimeError(message)
    return value


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    @override
    def redirect_request(self, *_args: object, **_kwargs: object) -> None:
        """Reject all redirects from the private service."""
        return


def _request(
    base: str,
    path: str,
    method: str = "GET",
    data: dict | None = None,
    credential: tuple[str, str] | None = None,
) -> dict | list:
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    if credential is not None:
        headers[credential[0]] = credential[1]
    req = urllib.request.Request(  # ruff: ignore[suspicious-url-open-usage]
        base + path,
        data=json.dumps(data).encode() if data is not None else None,
        headers=headers,
        method=method,
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())
    try:
        with opener.open(req, timeout=15) as response:
            if response.status not in {200, 201}:
                message = f"BookOrbit {path} returned HTTP {response.status}"
                raise RuntimeError(message)
            result = json.load(response)
    except urllib.error.HTTPError as error:
        message = f"BookOrbit {path} returned HTTP {error.code}"
        error.close()
        raise RuntimeError(message) from None
    if not isinstance(result, (dict, list)):
        message = f"BookOrbit {path} returned invalid JSON"
        raise TypeError(message)
    return result


def _ensure_libraries(base: str, token: str, specs: list[dict]) -> list[dict]:
    authorization = ("Authorization", f"Bearer {token}")
    libraries = _request(base, "/api/v1/libraries", credential=authorization)
    if not isinstance(libraries, list):
        message = "BookOrbit libraries response is invalid"
        raise TypeError(message)
    for spec in specs:
        path = spec["folders"][0]
        matches = [
            library
            for library in libraries
            if isinstance(library, dict)
            and any(
                isinstance(folder, dict) and folder.get("path") == path
                for folder in library.get("folders", [])
            )
        ]
        if len(matches) > 1:
            message = f"Multiple BookOrbit libraries use {path}"
            raise RuntimeError(message)
        if matches:
            continue
        if any(
            isinstance(library, dict) and library.get("name") == spec["name"]
            for library in libraries
        ):
            message = f"BookOrbit library name already exists: {spec['name']}"
            raise RuntimeError(message)
        created = _request(
            base,
            "/api/v1/libraries",
            "POST",
            {
                **spec,
                "type": "books",
                "watch": True,
                "fileWriteEnabled": False,
                "fileRenameEnabled": False,
            },
            credential=authorization,
        )
        if not isinstance(created, dict) or not isinstance(created.get("id"), int):
            message = "BookOrbit did not confirm library creation"
            raise TypeError(message)
        libraries.append(created)
    verified = _request(base, "/api/v1/libraries", credential=authorization)
    if not isinstance(verified, list):
        message = "BookOrbit libraries response is invalid"
        raise TypeError(message)
    return verified


def _check_qbittorrent(settings: dict) -> tuple[str, str]:
    """Verify sealed credentials and the exact isolated category path.

    Returns:
        The Web UI username and password for BookOrbit's encrypted client record.

    Raises:
        RuntimeError: The Web UI rejects the credentials or the category differs.
        TypeError: The category inventory has an invalid shape.

    """
    acquisition = settings["acquisition"]
    base = acquisition["url"]
    parsed = urllib.parse.urlsplit(base)
    if (
        parsed.scheme != "http"
        or not parsed.hostname
        or parsed.path
        or parsed.query
        or parsed.fragment
    ):
        message = "qBittorrent must use a direct private HTTP origin"
        raise RuntimeError(message)
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
        _NoRedirect(),
    )
    credentials = (
        _credential("qbittorrent-username"),
        _credential("qbittorrent-password"),
    )
    login = urllib.request.Request(  # ruff: ignore[suspicious-url-open-usage] - Validated private origin.
        base + "/api/v2/auth/login",
        data=urllib.parse.urlencode({
            "username": credentials[0],
            "password": credentials[1],
        }).encode(),
        headers={"Origin": base, "Referer": base + "/"},
        method="POST",
    )
    try:
        with opener.open(login, timeout=15) as response:
            accepted = response.status in {
                200,
                204,
            } and response.read().strip() not in {b"Fails.", b"Fails"}
    except urllib.error.HTTPError as error:
        error.close()
        message = f"qBittorrent Web UI check returned HTTP {error.code}"
        raise RuntimeError(message) from None
    if not accepted:
        message = "qBittorrent rejected the sealed Web UI credentials"
        raise RuntimeError(message)
    categories = urllib.request.Request(  # ruff: ignore[suspicious-url-open-usage] - Validated private origin.
        base + "/api/v2/torrents/categories",
        headers={"Referer": base + "/"},
    )
    try:
        with opener.open(categories, timeout=15) as response:
            if response.status != 200:  # ruff: ignore[magic-value-comparison] - HTTP success status.
                message = "qBittorrent category inventory is unavailable"
                raise RuntimeError(message)
            rows = json.load(response)
    except urllib.error.HTTPError as error:
        error.close()
        message = f"qBittorrent category check returned HTTP {error.code}"
        raise RuntimeError(message) from None
    if not isinstance(rows, dict) or not isinstance(
        rows.get(acquisition["category"]), dict
    ):
        message = "qBittorrent book category is missing"
        raise TypeError(message)
    if rows[acquisition["category"]].get("savePath") != acquisition["downloadDir"]:
        message = "qBittorrent book category has the wrong save path"
        raise RuntimeError(message)
    return credentials


def _ensure_download_client(base: str, token: str, settings: dict) -> None:
    acquisition = settings["acquisition"]
    username, password = _check_qbittorrent(settings)
    auth = ("Authorization", f"Bearer {token}")
    path = "/api/v1/admin/download-clients"
    inventory = _request(base, path, credential=auth)
    if not isinstance(inventory, dict) or not isinstance(
        inventory.get("clients"), list
    ):
        message = "BookOrbit download client inventory is invalid"
        raise TypeError(message)
    if inventory.get("encryptionConfigured") is not True:
        message = "BookOrbit cannot encrypt download client credentials"
        raise RuntimeError(message)
    matches = [
        row
        for row in inventory["clients"]
        if isinstance(row, dict) and row.get("name") == acquisition["name"]
    ]
    if len(matches) > 1:
        message = "Duplicate BookOrbit book download clients"
        raise RuntimeError(message)
    desired = {
        "name": acquisition["name"],
        "adapterType": "qbittorrent",
        "baseUrl": acquisition["url"],
        "username": username,
        "password": password,
        "enabled": True,
        "priority": 1,
        "category": acquisition["category"],
        "useHardlinks": True,
        "allowPrivateAddress": True,
        "pathMappings": [
            {
                "remotePath": acquisition["downloadDir"],
                "localPath": acquisition["localDownloadDir"],
            }
        ],
    }
    if matches:
        client = matches[0]
        if client.get("adapterType") != "qbittorrent" or not isinstance(
            client.get("id"), int
        ):
            message = "BookOrbit book download client has unexpected type"
            raise RuntimeError(message)
        client_id = client["id"]
        saved = _request(base, f"{path}/{client_id}", "PUT", desired, auth)
    else:
        saved = _request(base, path, "POST", desired, auth)
    if not isinstance(saved, dict) or not isinstance(saved.get("id"), int):
        message = "BookOrbit did not save the book download client"
        raise TypeError(message)
    client_id = saved["id"]
    tested = _request(base, f"{path}/{client_id}/test", "POST", credential=auth)
    if not isinstance(tested, dict) or tested.get("success") is not True:
        message = "BookOrbit cannot connect to qBittorrent"
        raise RuntimeError(message)
    mappings = saved.get("pathMappings")
    if (
        not isinstance(mappings, list)
        or len(mappings) != 1
        or not isinstance(mappings[0].get("id"), int)
    ):
        message = "BookOrbit did not save the isolated import mapping"
        raise TypeError(message)
    probe = _request(
        base,
        f"{path}/{client_id}/test-path-mapping",
        "POST",
        {"mappingId": mappings[0]["id"]},
        auth,
    )
    if not isinstance(probe, dict) or probe.get("hardlinkWorks") is not True:
        message = "BookOrbit cannot hardlink from the download category into Book Dock"
        raise RuntimeError(message)


def _ensure_automation(
    base: str, token: str, settings: dict, libraries: list[dict]
) -> None:
    acquisition = settings["acquisition"]
    destinations = {}
    for medium, name in acquisition["destinations"].items():
        matches = [
            row
            for row in libraries
            if isinstance(row, dict) and row.get("name") == name
        ]
        if len(matches) != 1 or not isinstance(matches[0].get("id"), int):
            message = f"BookOrbit destination library is missing or ambiguous: {name}"
            raise RuntimeError(message)
        folders = matches[0].get("folders")
        if (
            not isinstance(folders, list)
            or not folders
            or not isinstance(folders[0].get("id"), int)
        ):
            message = f"BookOrbit destination folder is missing: {name}"
            raise RuntimeError(message)
        destinations[medium] = {
            "libraryId": matches[0]["id"],
            "folderId": folders[0]["id"],
        }
    auth = ("Authorization", f"Bearer {token}")
    path = "/api/v1/admin/book-request-automation"
    _request(
        base,
        path,
        "PUT",
        {
            "autoGrabEnabled": True,
            "autoGrabMinScore": acquisition["minReleaseScore"],
            "autoRetryEnabled": False,
            "maxAutoGrabAttempts": 1,
            "autoSearchEnabled": False,
            "verificationEnabled": True,
            "verificationThreshold": acquisition["minImportScore"],
            "destinations": destinations,
        },
        auth,
    )
    current = _request(base, path, credential=auth)
    if (
        not isinstance(current, dict)
        or current.get("autoGrabEnabled") is not True
        or current.get("destinations") != destinations
    ):
        message = "BookOrbit request automation was not saved"
        raise RuntimeError(message)


def _book_category_ids(categories: object) -> set[int]:
    """Collect Prowlarr's nested standardized categories.

    Returns:
        Every numeric category ID in the tree.

    """
    ids: set[int] = set()
    if not isinstance(categories, list):
        return ids
    for category in categories:
        if not isinstance(category, dict):
            continue
        category_id = category.get("id")
        if isinstance(category_id, int):
            ids.add(category_id)
        ids.update(_book_category_ids(category.get("subCategories")))
    return ids


def _matches_vpn_proxy(row: object, tags: set[int], expected: dict) -> bool:
    if not isinstance(row, dict) or not isinstance(row.get("fields"), list):
        return False
    fields = {
        field.get("name"): field.get("value")
        for field in row["fields"]
        if isinstance(field, dict)
    }
    return (
        row.get("implementation") == "Socks5"
        and row.get("name") == expected["name"]
        and isinstance(row.get("tags"), list)
        and bool(tags.intersection(row["tags"]))
        and fields.get("host") == expected["host"]
        and fields.get("port") == expected["port"]
    )


def _prowlarr_inventory(prowlarr: str, key: str) -> tuple[list, list]:
    """Wait for the local socket bridge before reading Prowlarr's sources.

    Returns:
        The Prowlarr tag and indexer lists.

    Raises:
        RuntimeError: The local bridge did not become ready.
        TypeError: Prowlarr returned invalid inventory data.

    """
    deadline = time.monotonic() + 60
    api_key = ("X-Api-Key", key)
    while True:
        try:
            tag_rows = _request(prowlarr, "/api/v1/tag", credential=api_key)
            indexer_rows = _request(prowlarr, "/api/v1/indexer", credential=api_key)
        except urllib.error.URLError:
            if time.monotonic() >= deadline:
                message = "The local Prowlarr bridge did not start within one minute"
                raise RuntimeError(message) from None
            time.sleep(2)
        else:
            if not isinstance(tag_rows, list) or not isinstance(indexer_rows, list):
                message = "Prowlarr indexer or tag response is invalid"
                raise TypeError(message)
            return tag_rows, indexer_rows


def _allowed_vpn_sources(prowlarr: str, key: str, settings: dict) -> set[str]:
    """Select only book-capable torrent sources routed through Prowlarr's VPN.

    Returns:
        Prowlarr source IDs permitted for BookOrbit release searches.

    Raises:
        RuntimeError: The VPN route tag or a usable source is missing.
        TypeError: Prowlarr returns invalid proxy data.

    """
    tag_rows, indexer_rows = _prowlarr_inventory(prowlarr, key)
    proxies = _request(
        prowlarr,
        "/api/v1/indexerProxy",
        credential=("X-Api-Key", key),
    )
    if not isinstance(proxies, list):
        message = "Prowlarr proxy inventory is invalid"
        raise TypeError(message)
    vpn_tags = {
        row["id"]
        for row in tag_rows
        if isinstance(row, dict)
        and isinstance(row.get("id"), int)
        and row.get("label") == settings["vpnTag"]
    }
    if not vpn_tags:
        message = "Prowlarr has no VPN route tag"
        raise RuntimeError(message)
    expected = settings["proxy"]
    routed = [row for row in proxies if _matches_vpn_proxy(row, vpn_tags, expected)]
    if len(routed) != 1:
        message = "Prowlarr VPN SOCKS proxy is missing or ambiguous"
        raise RuntimeError(message)
    allowed = {
        str(row["id"])
        for row in indexer_rows
        if isinstance(row, dict)
        and isinstance(row.get("id"), int)
        and row.get("enable") is True
        and row.get("protocol") == "torrent"
        and isinstance(row.get("tags"), list)
        and vpn_tags.intersection(row["tags"])
        and isinstance(row.get("capabilities"), dict)
        and _book_category_ids(row["capabilities"].get("categories")).intersection(
            settings["bookCategories"]
        )
    }
    if not allowed:
        message = "No enabled VPN-routed Prowlarr book sources"
        raise RuntimeError(message)
    return allowed


def _sync_bookorbit_manager(
    base: str, prowlarr: str, key: str, auth: tuple[str, str], name: str
) -> tuple[int, list]:
    """Reconcile BookOrbit's built-in Prowlarr manager.

    Returns:
        The manager ID and its synchronized source list.

    Raises:
        RuntimeError: The manager cannot connect or is duplicated.
        TypeError: BookOrbit returns invalid manager data.

    """
    path = "/api/v1/admin/request-indexer-managers"
    result = _request(base, path, credential=auth)
    if not isinstance(result, dict) or not isinstance(result.get("managers"), list):
        message = "BookOrbit indexer manager response is invalid"
        raise TypeError(message)
    matching = [
        item
        for item in result["managers"]
        if isinstance(item, dict) and item.get("name") == name
    ]
    if len(matching) > 1:
        message = "Duplicate BookOrbit Prowlarr managers"
        raise RuntimeError(message)
    desired = {
        "name": name,
        "baseUrl": prowlarr,
        "credential": key,
        "enabled": True,
        "allowPrivateAddress": True,
        "syncNewIndexers": False,
        "autoExpandCategories": False,
    }
    if matching:
        manager = matching[0]
        if manager.get("type") != "prowlarr" or not isinstance(manager.get("id"), int):
            message = "BookOrbit Prowlarr manager has unexpected type"
            raise RuntimeError(message)
        manager_id = manager["id"]
        _request(base, f"{path}/{manager_id}", "PUT", desired, auth)
    else:
        created = _request(base, path, "POST", {**desired, "type": "prowlarr"}, auth)
        if not isinstance(created, dict) or not isinstance(created.get("id"), int):
            message = "BookOrbit did not create Prowlarr manager"
            raise TypeError(message)
        manager_id = created["id"]
    tested = _request(base, f"{path}/{manager_id}/test", "POST", credential=auth)
    if not isinstance(tested, dict) or tested.get("success") is not True:
        message = "BookOrbit could not test Prowlarr"
        raise RuntimeError(message)
    synced = _request(base, f"{path}/{manager_id}/sync", "POST", credential=auth)
    if not isinstance(synced, dict) or not isinstance(synced.get("manager"), dict):
        message = "BookOrbit did not synchronize Prowlarr sources"
        raise TypeError(message)
    sources = synced["manager"].get("sources")
    if not isinstance(sources, list):
        message = "BookOrbit synchronized sources are invalid"
        raise TypeError(message)
    return manager_id, sources


def _reconcile_source(
    base: str,
    manager_id: int,
    source: dict,
    allowed_ids: set[str],
    auth: tuple[str, str],
) -> bool:
    """Enable one VPN-vetted source; report temporary test failures.

    Returns:
        Whether the source remains enabled behind the required VPN proxy.

    Raises:
        TypeError: BookOrbit returns an invalid source row.

    """
    if not isinstance(source.get("id"), int):
        message = "BookOrbit source is invalid"
        raise TypeError(message)
    source_id = source["id"]
    path = f"/api/v1/admin/request-indexer-managers/{manager_id}/sources/{source_id}"
    wanted = (
        source.get("externalId") in allowed_ids
        and source.get("adapterType") == "torznab"
        and source.get("available") is True
    )
    if source.get("enabled") is not wanted:
        _request(base, path, "PUT", {"enabled": wanted}, auth)
    if not wanted:
        return False
    # A manager restart should not re-test every existing tracker. Repeated
    # connection tests trigger rate limits and can close the entire site.
    if source.get("enabled") is True:
        return True
    try:
        tested = _request(
            base,
            f"/api/v1/admin/request-indexers/{source_id}/test",
            "POST",
            credential=auth,
        )
    except RuntimeError:
        tested = None
    if not isinstance(tested, dict) or tested.get("success") is not True:
        LOGGER.warning(
            "BookOrbit source test is temporarily unavailable; VPN-routed source remains enabled"
        )
    return True


def _ensure_sources(base: str, prowlarr: str, token: str, settings: dict) -> None:
    key = _credential("prowlarr-api-key")
    allowed_ids = _allowed_vpn_sources(prowlarr, key, settings)
    auth = ("Authorization", f"Bearer {token}")
    manager_id, sources = _sync_bookorbit_manager(
        base, prowlarr, key, auth, settings["managerName"]
    )
    enabled = sum(
        _reconcile_source(base, manager_id, source, allowed_ids, auth)
        for source in sources
        if isinstance(source, dict)
    )
    if enabled == 0:
        message = "BookOrbit has no enabled VPN-routed book sources"
        raise RuntimeError(message)
    status = _request(base, "/api/v1/book-requests/source-status", credential=auth)
    if not isinstance(status, dict) or status.get("enabled", 0) < enabled:
        message = "BookOrbit did not enable the book sources"
        raise RuntimeError(message)


def _wait_for_setup_status(base: str) -> dict:
    deadline = time.monotonic() + 60
    while True:
        try:
            status = _request(base, "/api/v1/auth/setup-status")
        except urllib.error.URLError:
            if time.monotonic() >= deadline:
                message = "BookOrbit did not start within one minute"
                raise RuntimeError(message) from None
            time.sleep(2)
        else:
            if not isinstance(status, dict):
                message = "BookOrbit setup status is invalid"
                raise TypeError(message)
            return status


def _main(base: str, prowlarr: str, settings: dict) -> None:
    username = _credential("admin-username")
    email = _credential("admin-email")
    password = _credential("admin-password")
    token = _credential("setup-token")
    status = _wait_for_setup_status(base)
    if status.get("allowRegistration") is not False:
        message = "BookOrbit registration must remain disabled"
        raise RuntimeError(message)
    if status.get("needsSetup") is True:
        _request(
            base,
            "/api/v1/auth/setup",
            "POST",
            {
                "username": username,
                "name": "Book administrator",
                "email": email,
                "password": password,
            },
            ("X-Setup-Token", token),
        )
    elif status.get("needsSetup") is not False:
        message = "BookOrbit setup status is invalid"
        raise RuntimeError(message)
    login = _request(
        base,
        "/api/v1/auth/login",
        "POST",
        {"username": username, "password": password},
    )
    if not isinstance(login, dict):
        message = "BookOrbit login response is invalid"
        raise TypeError(message)
    user = login.get("user")
    if (
        not isinstance(user, dict)
        or user.get("username") != username
        or user.get("isSuperuser") is not True
    ):
        message = "BookOrbit sealed administrator was not verified"
        raise RuntimeError(message)
    access_token = login.get("accessToken")
    if not isinstance(access_token, str) or not access_token:
        message = "BookOrbit did not issue an access token"
        raise RuntimeError(message)
    libraries = _ensure_libraries(base, access_token, settings["libraries"])
    _ensure_sources(base, prowlarr, access_token, settings)
    if settings.get("acquisition", {}).get("enabled") is True:
        _ensure_download_client(base, access_token, settings)
        _ensure_automation(base, access_token, settings, libraries)
    Path(
        os.environ.get("BOOKORBIT_READY_DIR", "/run/bookorbit-bootstrap"),
        "ready",
    ).touch()


if __name__ == "__main__":
    with Path(sys.argv[3]).open(encoding="utf-8") as file:
        settings = json.load(file)
    _main(sys.argv[1], sys.argv[2], settings)
