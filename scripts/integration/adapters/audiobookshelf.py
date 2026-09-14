"""Reconcile Audiobookshelf bootstrap, libraries and accounts."""

import json
import os
from pathlib import Path

from common import ConfigurationError, contains, password_fingerprint


def reconcile_audiobookshelf(client, config, dry_run):
    settings = config["settings"]
    status = client.request("GET", "/status")
    if not status["isInit"]:
        if dry_run:
            return {"bootstrapRequired": True}
        login = settings["login"]
        if not login.get("password"):
            raise ConfigurationError(
                "Initial audiobook administrator requires a password"
            )
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
        declared.update({
            "username": name,
            "type": spec.get("type", "user"),
            "isActive": spec.get("isActive", True),
        })
        digest = (
            password_fingerprint(
                spec["password"], state.get(current["id"]) if current else None
            )
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
                        temporary,
                        "w",
                        encoding="utf-8",
                        opener=lambda path, flags: os.open(path, flags, 0o600),
                    ) as handle:
                        json.dump(state, handle)
                    temporary.replace(state_path)
    return {"changed": changed}
