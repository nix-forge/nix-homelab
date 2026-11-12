"""Exercise the public BookOrbit API with disposable VM-local credentials."""

import json
import sys
import urllib.request
from pathlib import Path

credentials = Path("/run/bookorbit-fixture")
address = Path("/etc/native-bookorbit-address").read_text(encoding="utf-8").strip()
base = "http://" + address + ":13006"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def request(path, body=None, token=None, setup=False):
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    if setup:
        headers["X-Setup-Token"] = (credentials / "setup-token").read_text(
            encoding="utf-8"
        )
    call = urllib.request.Request(
        base + path,
        headers=headers,
        data=None if body is None else json.dumps(body).encode(),
    )
    with opener.open(call, timeout=15) as response:
        assert response.status in {200, 201}
        return json.load(response)


mode = sys.argv[1]
if mode == "health":
    with opener.open(base + "/api/v1/health", timeout=5) as response:
        assert response.status == 200
    sys.exit(0)
if mode == "inventory":
    inventory = json.loads(
        Path("/etc/homelab/state-inventory.json").read_text(encoding="utf-8")
    )
    service = inventory["bookorbit"]
    assert "/var/lib/bookorbit" in service["paths"]
    assert {"bookorbit.service", "bookorbit-native-db.service"} <= set(service["units"])
    sys.exit(0)
status = request("/api/v1/auth/setup-status")
assert status["allowRegistration"] is False
if mode == "setup":
    assert status["needsSetup"] is True
    request(
        "/api/v1/auth/setup",
        {
            "username": (credentials / "admin-username").read_text(encoding="utf-8"),
            "name": "Native fixture administrator",
            "email": (credentials / "admin-email").read_text(encoding="utf-8"),
            "password": (credentials / "admin-password").read_text(encoding="utf-8"),
        },
        setup=True,
    )
else:
    assert status["needsSetup"] is False
login = request(
    "/api/v1/auth/login",
    {
        "username": (credentials / "admin-username").read_text(encoding="utf-8"),
        "password": (credentials / "admin-password").read_text(encoding="utf-8"),
    },
)
assert login["user"]["isSuperuser"] is True
assert login["user"]["username"] == "fixture-admin"
token = login["accessToken"]
assert isinstance(token, str)
assert token
if mode == "create":
    created = request(
        "/api/v1/libraries",
        {
            "name": "Native recovery fixture",
            "icon": "BookOpen",
            "type": "books",
            "folders": ["/books/books"],
            "allowedFormats": ["epub"],
            "organizationMode": "book_per_file",
            "watch": True,
            "fileWriteEnabled": False,
            "fileRenameEnabled": False,
        },
        token,
    )
    assert isinstance(created["id"], int)
libraries = request("/api/v1/libraries", token=token)
if mode in {"create", "verify"}:
    matches = [row for row in libraries if row["name"] == "Native recovery fixture"]
    assert len(matches) == 1
    library = matches[0]
    assert library["fileWriteEnabled"] is False
    assert any(folder["path"] == "/books/books" for folder in library["folders"])
    # Only public state identity leaves this helper; never output login tokens.
    print(json.dumps({"id": library["id"], "name": library["name"]}))
