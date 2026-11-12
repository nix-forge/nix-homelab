"""Replace Keycloak's temporary bootstrap administrator without logging credentials."""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("unexpected identity redirect")


def request(base, path, *, data=None, token=None, form=False, method=None):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
    if data is not None:
        if form:
            data = urllib.parse.urlencode(data).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(data).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    with opener.open(req, timeout=20) as response:
        raw = response.read(1024 * 1024)
        return json.loads(raw) if raw else None


def login(base, username, password):
    return request(
        base,
        "/realms/master/protocol/openid-connect/token",
        form=True,
        data={
            "client_id": "admin-cli",
            "grant_type": "password",
            "username": username,
            "password": password,
        },
    )["access_token"]


def ensure_admin(base, admin, password, temporary, temporary_password):
    if admin == temporary:
        raise ValueError("bootstrap and permanent administrator collide")
    try:
        token = login(base, admin, password)
        request(base, "/admin/realms/master", token=token)
    except urllib.error.HTTPError as error:
        if error.code not in {400, 401, 403}:
            raise
        token = login(base, temporary, temporary_password)
    users = request(
        base,
        "/admin/realms/master/users?"
        + urllib.parse.urlencode({"username": admin, "exact": "true"}),
        token=token,
    )
    if not users:
        request(
            base,
            "/admin/realms/master/users",
            token=token,
            data={
                "username": admin,
                "enabled": True,
                "requiredActions": [],
                "firstName": "System",
                "lastName": "Operator",
                "email": admin + "@localhost.invalid",
                "emailVerified": True,
                "credentials": [
                    {"type": "password", "value": password, "temporary": False}
                ],
            },
        )
        users = request(
            base,
            "/admin/realms/master/users?"
            + urllib.parse.urlencode({"username": admin, "exact": "true"}),
            token=token,
        )
    if len(users) != 1:
        raise ValueError("ambiguous administrator")
    role = request(base, "/admin/realms/master/roles/admin", token=token)
    request(
        base,
        "/admin/realms/master/users/" + users[0]["id"] + "/role-mappings/realm",
        token=token,
        data=[{"id": role["id"], "name": role["name"]}],
    )
    # Prove the permanent account works before removing the temporary account.
    token = login(base, admin, password)
    request(base, "/admin/realms/master", token=token)
    old = request(
        base,
        "/admin/realms/master/users?"
        + urllib.parse.urlencode({"username": temporary, "exact": "true"}),
        token=token,
    )
    for user in old:
        if user["id"] == users[0]["id"]:
            raise ValueError("bootstrap and permanent administrator collide")
        request(
            base,
            "/admin/realms/master/users/" + user["id"],
            token=token,
            method="DELETE",
        )


def main():
    try:
        marker = Path(os.environ["STATE_DIRECTORY"]) / "administrator-provisioned"
        if marker.is_file():
            return 0

        ensure_admin(
            os.environ["HOMELAB_KEYCLOAK_URL"],
            os.environ["HOMELAB_ADMIN_USERNAME"],
            os.environ["HOMELAB_ADMIN_PASSWORD"],
            os.environ["KC_BOOTSTRAP_ADMIN_USERNAME"],
            os.environ["KC_BOOTSTRAP_ADMIN_PASSWORD"],
        )
    except OSError, ValueError, KeyError:
        print(
            "Keycloak administrator provisioning failed; sensitive responses suppressed",
            file=sys.stderr,
        )
        return 1
    marker.touch(mode=0o600, exist_ok=False)
    print("Permanent administrator verified; temporary bootstrap account removed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
