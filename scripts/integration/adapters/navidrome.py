"""Reconcile Navidrome bootstrap and accounts."""

import json
import os
from pathlib import Path

from common import APIError, ConfigurationError, merge, password_fingerprint


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
        matches = [
            user for user in users if user["userName"].casefold() == name.casefold()
        ]
        if len(matches) > 1:
            raise ConfigurationError("Ambiguous audio account")
        current = matches[0] if matches else None
        if current and config["mode"] == "bootstrap":
            continue
        declared = {key: value for key, value in spec.items() if key != "password"}
        declared.update({
            "userName": current["userName"] if current else name,
            "isAdmin": spec.get("isAdmin", False),
        })
        if not current and not spec.get("password"):
            raise ConfigurationError("New accounts require a nonempty runtime password")
        desired = merge(current or {}, declared)
        digest = (
            password_fingerprint(
                spec["password"], state.get(current["id"]) if current else None
            )
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
                        temporary,
                        "w",
                        encoding="utf-8",
                        opener=lambda path, flags: os.open(path, flags, 0o600),
                    ) as handle:
                        json.dump(state, handle)
                    temporary.replace(state_path)
    return {"changed": changed}
