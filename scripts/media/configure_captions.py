"""Apply a Moonfin caption preset once per managed user, preserving later edits."""

import argparse
import http.client
import json
import os
import re
import sys
import uuid
from dataclasses import dataclass, field
from http import HTTPStatus
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


class CaptionError(Exception):
    """A sanitized caption provisioning failure."""


class ApiError(Exception):
    """An API status without credential-bearing response content."""

    def __init__(self, status: int) -> None:
        """Retain only the HTTP status for callers."""
        self.status = status
        super().__init__(f"Caption API returned HTTP {status}")


class Client:
    """Loopback-only API client without proxies or redirects."""

    def __init__(
        self,
        port: int,
        *,
        host: str = "127.0.0.1",
        tls: bool = False,
        base_path: str = "",
    ) -> None:
        """Select the local server port."""
        self.port = port
        self.host = host
        self.tls = tls
        self.base_path = base_path.rstrip("/")
        self.token: str | None = None

    def request(self, method: str, path: str, payload: Any = None) -> Any:  # ruff: ignore[any-type] - extensible API JSON
        """Exchange API JSON.

        Returns:
            The decoded JSON body, or None for an empty response.

        Raises:
            ApiError: The server rejects the request, including redirects.

        """
        headers = {
            "Content-Type": "application/json",
            "Authorization": 'MediaBrowser Client="Caption setup", '
            'Device="Server", DeviceId="caption-setup", Version="1"',
        }
        if self.token:
            headers["Authorization"] += f', Token="{self.token}"'
        connection_type = (
            http.client.HTTPSConnection if self.tls else http.client.HTTPConnection
        )
        connection = connection_type(self.host, self.port, timeout=15)
        try:
            connection.request(
                method,
                self.base_path + path,
                body=None if payload is None else json.dumps(payload),
                headers=headers,
            )
            response = connection.getresponse()
            if not HTTPStatus.OK <= response.status < HTTPStatus.MULTIPLE_CHOICES:
                raise ApiError(response.status)
            body = response.read()
            return json.loads(body) if body else None
        finally:
            connection.close()


@dataclass(frozen=True)
class CaptionPolicy:
    """Account selection and the operator's explicit preset migration history."""

    username_credentials: list[str]
    revision: str
    previous_revision: str | None = None
    previous_profiles: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        """Reject unsafe completion-marker revisions and credential identifiers.

        Raises:
            CaptionError: The preset metadata is unsafe.

        """
        identifiers = [self.revision, *self.username_credentials]
        if self.previous_revision is not None:
            identifiers.append(self.previous_revision)
        if not self.username_credentials or any(
            re.fullmatch(r"[A-Za-z0-9_-]+", item) is None for item in identifiers
        ):
            raise CaptionError(
                "Caption revisions and credential identifiers must be safe names"
            )


def configure(
    client: Client,
    credentials: Path,
    state: Path,
    preset: dict[str, Any],
    policy: CaptionPolicy,
) -> None:
    """Merge only caption fields, then record successful provisioning.

    Raises:
        CaptionError: Managed accounts or settings sync are not ready.
        ApiError: The server rejects a request.

    """
    login = client.request(
        "POST",
        "/Users/AuthenticateByName",
        {
            "Username": (credentials / "admin-username")
            .read_text(encoding="utf-8")
            .rstrip("\r\n"),
            "Pw": (credentials / "admin-password")
            .read_text(encoding="utf-8")
            .rstrip("\r\n"),
        },
    )
    client.token = login["AccessToken"]
    try:
        server = uuid.UUID(login["ServerId"]).hex
        users = client.request("GET", "/Users")
        names = {
            (credentials / name).read_text(encoding="utf-8").rstrip("\r\n")
            for name in policy.username_credentials
        }
        selected = [user for user in users if user["Name"] in names]
        if {user["Name"] for user in selected} != names:
            message = "Managed caption accounts are not ready"
            raise CaptionError(message)
        state.mkdir(mode=0o700, parents=True, exist_ok=True)
        for user in selected:
            user_id = uuid.UUID(user["Id"]).hex
            marker = state / f"{server}-{user_id}-{policy.revision}"
            if marker.exists():
                continue
            try:
                current = client.request("GET", f"/Moonfin/Settings/{user_id}")
            except ApiError as error:
                if error.status != HTTPStatus.NOT_FOUND:
                    raise
                current = {}
            if current.get("syncEnabled") is False:
                message = "Enable Moonfin settings sync before caption setup"
                raise CaptionError(message)
            updates = preset
            if (
                policy.previous_revision is not None
                and (state / f"{server}-{user_id}-{policy.previous_revision}").exists()
            ):
                # Only update fields still equal to the operator's previous preset.
                updates = {}
                for profile, settings in preset.items():
                    previous = policy.previous_profiles.get(profile, {})
                    saved = current.get(profile, {})
                    updates[profile] = {
                        key: value
                        for key, value in settings.items()
                        if key not in saved
                        or (key in previous and saved[key] == previous[key])
                    }
            client.request(
                "POST",
                f"/Moonfin/Settings/{user_id}",
                {
                    "settings": {"schemaVersion": 2, **updates},
                    "clientId": "nix-caption-setup",
                    "mergeMode": "merge",
                },
            )
            marker.touch(mode=0o600)
    finally:
        client.request("POST", "/Sessions/Logout")


def main() -> None:
    """Run with systemd credentials and private persistent state."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    args = parser.parse_args()
    try:
        settings = json.loads(args.configuration.read_text(encoding="utf-8"))
        url = urlsplit(settings["serverUrl"])
        configure(
            Client(
                url.port or (443 if url.scheme == "https" else 80),
                host=url.hostname,
                tls=url.scheme == "https",
                base_path=url.path,
            ),
            Path(os.environ["CREDENTIALS_DIRECTORY"]),
            Path(os.environ["STATE_DIRECTORY"]),
            settings["profiles"],
            CaptionPolicy(
                username_credentials=settings["usernameCredentials"],
                revision=settings["revision"],
                previous_revision=settings["previousRevision"],
                previous_profiles=settings["previousProfiles"],
            ),
        )
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        AttributeError,
        CaptionError,
        ApiError,
        http.client.HTTPException,
    ) as error:
        # API bodies and request objects may contain credentials; never log them.
        sys.exit(
            str(error)
            if isinstance(error, CaptionError)
            else f"Caption setup failed ({type(error).__name__}); check Jellyfin and Moonbase availability"
        )


if __name__ == "__main__":
    main()
