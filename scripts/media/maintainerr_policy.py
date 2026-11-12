"""Conservative, explicitly invoked Maintainerr v3.28 policy reconciliation."""

import argparse
import json
import os
import pathlib
import tempfile
import urllib.error
import urllib.parse
import urllib.request

IDENTITY = ("libraryId", "dataType", "manualCollection", "manualCollectionName")


def request(base, method, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        base + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        raise RuntimeError(
            f"Maintainerr {method} {path} returned HTTP {error.code}"
        ) from None
    return json.loads(body) if body else None


def load_json(path, default):
    try:
        with pathlib.Path(path).open(encoding="utf-8") as stream:
            return json.load(stream)
    except FileNotFoundError:
        return default


def save_ledger(path, ledger):
    parent = pathlib.Path(path).parent
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=parent, prefix=".policy-")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(ledger, stream, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        pathlib.Path(temporary).replace(path)
    finally:
        if pathlib.Path(temporary).exists():
            pathlib.Path(temporary).unlink()


def validate(policy):
    if set(policy) - {"rules", "templates", "overlaySettings"}:
        raise ValueError("unsupported policy section")
    for kind in ("rules", "templates"):
        entries = policy.get(kind, [])
        if not isinstance(entries, list):
            raise ValueError(f"{kind} must be a list")
        names = [item.get("name") for item in entries]
        if any(not isinstance(name, str) or not name for name in names):
            raise ValueError(f"{kind} needs nonempty names")
        if len(names) != len(set(names)):
            raise ValueError(f"duplicate {kind} name")
    for rule in policy.get("rules", []):
        collection = rule.get("collection")
        if not isinstance(collection, dict):
            raise ValueError("each rule needs a collection")
        days = collection.get("deleteAfterDays")
        if type(days) is not int or not 1 <= days <= 36500:
            raise ValueError("deleteAfterDays must be from 1 to 36500")
        if rule.get("arrAction") != 4:
            raise ValueError("only DO_NOTHING (arrAction 4) is allowed")
        if collection.get("arrAction", 4) != 4:
            raise ValueError("collection action must be DO_NOTHING")
        if collection.get("overlayEnabled") is not False:
            raise ValueError("rule overlays must be disabled")
        for field in (
            "description",
            "libraryId",
            "dataType",
            "rules",
            "useRules",
            "isActive",
        ):
            if field not in rule:
                raise ValueError(f"rule {rule['name']} needs {field}")
        if type(rule["isActive"]) is not bool:
            raise ValueError("isActive must be a boolean")
        if type(rule["useRules"]) is not bool:
            raise ValueError("useRules must be a boolean")
        if rule["dataType"] not in ("movie", "show", "season", "episode"):
            raise ValueError("unsupported dataType")
        if type(rule["libraryId"]) not in (int, str):
            raise ValueError("libraryId must match an upstream ID")
        for field in ("manualCollection", "manualCollectionName"):
            if field not in collection:
                raise ValueError(f"collection needs {field}")
        if not isinstance(rule["rules"], list):
            raise ValueError("rules must be a list")
        if rule.get("forceSeerr", False):
            raise ValueError("forceSeerr is outside this safe phase")
    settings = policy.get("overlaySettings")
    if settings is not None and settings != {"enabled": False}:
        raise ValueError("only disabled overlay settings are supported")
    for template in policy.get("templates", []):
        for field in ("mode", "canvasWidth", "canvasHeight", "elements"):
            if field not in template:
                raise ValueError(f"template {template['name']} needs {field}")
        if template["mode"] not in ("poster", "titlecard"):
            raise ValueError("unsupported template mode")
        if template.get("isDefault"):
            raise ValueError("default selection is outside this safe phase")


def field_matches(existing, key, desired):
    if key == "arrAction":
        collection = existing.get("collection") or {}
        return collection.get("arrAction", existing.get(key)) == desired
    if key == "collection":
        stored = existing.get("collection") or {}
        return all(stored.get(field) == value for field, value in desired.items())
    if key == "libraryId":
        return str(existing.get(key)) == str(desired)
    if key == "rules":
        stored = existing.get("rules") or []
        if len(stored) != len(desired):
            return False
        for row, wanted in zip(stored, desired, strict=True):
            parsed = row.get("ruleJson", row)
            if isinstance(parsed, str):
                parsed = json.loads(parsed)
            if not isinstance(parsed, dict):
                return False
            for field, value in wanted.items():
                actual = row.get(field) if field == "section" else parsed.get(field)
                if actual != value:
                    return False
        return True
    return existing.get(key) == desired


def reconcile(base, policy, ledger_path, apply):
    ledger = load_json(ledger_path, {"rules": {}, "templates": {}})
    if not isinstance(ledger, dict):
        raise ValueError("invalid ownership ledger")
    for kind, endpoint in (
        ("rules", "/api/rules"),
        ("templates", "/api/overlays/templates"),
    ):
        if not policy.get(kind):
            continue
        owned = ledger.setdefault(kind, {})
        current = request(base, "GET", endpoint)
        if not isinstance(current, list):
            raise RuntimeError(f"unexpected {kind} API response")
        by_name = {}
        for item in current:
            by_name.setdefault(item["name"], []).append(item)
        for desired in policy.get(kind, []):
            name = desired["name"]
            matches = by_name.get(name, [])
            if len(matches) > 1:
                raise RuntimeError(f"duplicate upstream {kind}: {name}")
            existing = matches[0] if matches else None
            if existing and owned.get(name) != existing["id"]:
                raise RuntimeError(f"unowned {kind} name collision: {name}")
            if not existing and name in owned:
                raise RuntimeError(f"owned {kind} missing upstream: {name}")
            if kind == "rules" and existing:
                old_collection = existing.get("collection") or {}
                new_collection = desired["collection"]
                for field in IDENTITY:
                    old = (
                        old_collection if field.startswith("manual") else existing
                    ).get(field)
                    new = (
                        new_collection if field.startswith("manual") else desired
                    ).get(field)
                    if field == "libraryId":
                        # Keep the server's exact representation in PUT.
                        old, new = str(old), str(new)
                    if old != new:
                        raise RuntimeError(f"rule identity changed: {name}: {field}")
            if kind == "templates" and existing and existing.get("isPreset"):
                raise RuntimeError(f"cannot own preset template: {name}")
            if (
                kind == "templates"
                and existing
                and existing.get("mode") != desired["mode"]
            ):
                raise RuntimeError(f"template mode changed: {name}")
            changed = existing is None or any(
                not field_matches(existing, key, value)
                for key, value in desired.items()
            )
            action = (
                "create" if existing is None else ("update" if changed else "unchanged")
            )
            print(f"{kind}: {action}: {name}")
            if not apply or not changed:
                continue
            if kind == "rules":
                payload = dict(desired)
                if existing:
                    payload["id"] = existing["id"]
                    payload["libraryId"] = existing["libraryId"]
                    payload["collection"] = {
                        **(existing.get("collection") or {}),
                        **desired["collection"],
                        "arrAction": 4,
                        "overlayEnabled": False,
                    }
                result = request(base, "PUT" if existing else "POST", endpoint, payload)
                if not isinstance(result, dict) or result.get("code") != 1:
                    raise RuntimeError(f"rule write failed: {name}")
            else:
                path = endpoint + (f"/{existing['id']}" if existing else "")
                result = request(base, "PUT" if existing else "POST", path, desired)
                if not isinstance(result, dict) or "id" not in result:
                    raise RuntimeError(f"template write failed: {name}")
                if not existing:
                    owned[name] = result["id"]
                    save_ledger(ledger_path, ledger)
            if not existing:
                if kind == "templates":
                    continue
                refreshed = request(base, "GET", endpoint)
                created = [item for item in refreshed if item.get("name") == name]
                if len(created) != 1:
                    raise RuntimeError(f"created {kind} cannot be identified: {name}")
                owned[name] = created[0]["id"]
                save_ledger(ledger_path, ledger)
    if "overlaySettings" in policy:
        current = request(base, "GET", "/api/overlays/settings")
        if not isinstance(current, dict):
            raise RuntimeError("unexpected overlay settings response")
        if current.get("enabled") is not False:
            print("overlaySettings: disable")
            if apply:
                request(base, "PUT", "/api/overlays/settings", {"enabled": False})
        else:
            print("overlaySettings: unchanged")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("plan", "apply"))
    parser.add_argument("--config", required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--url", default="http://127.0.0.1:6247")
    args = parser.parse_args()
    target = urllib.parse.urlsplit(args.url)
    if (
        target.scheme != "http"
        or target.hostname != "127.0.0.1"
        or target.port is None
        or target.username is not None
        or target.path
        or target.query
        or target.fragment
    ):
        parser.error("only a local Maintainerr backend is supported")
    policy = load_json(args.config, None)
    if not isinstance(policy, dict):
        parser.error("policy file must be a JSON object")
    validate(policy)
    reconcile(args.url, policy, args.ledger, args.action == "apply")


if __name__ == "__main__":
    main()
