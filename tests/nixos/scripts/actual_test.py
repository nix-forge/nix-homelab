"""Exercise actual with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    client: QemuMachine = cast("QemuMachine", None)
    server: QemuMachine = cast("QemuMachine", None)

import json
from datetime import timedelta

server.wait_for_unit("actual.service")
server.wait_until_succeeds(
    "curl -fsS http://127.0.0.1:5006/health", timeout=timedelta(minutes=3)
)
health = json.loads(server.succeed("curl -fsS http://127.0.0.1:5006/health"))
assert health == {"status": "UP"}, health
headers = server.succeed("curl -sS -D - -o /dev/null http://127.0.0.1:5006/").lower()
assert headers.count("cross-origin-opener-policy:") == 1, headers
assert headers.count("cross-origin-embedder-policy:") == 1, headers

# A listener bound to loopback must not accept traffic from another host,
# even if a future firewall rule accidentally opens the same port.
client.fail("curl -fsS --max-time 3 http://server:5006/health")
assert (
    json.loads(
        server.succeed("curl -fsS http://127.0.0.1:5006/account/needs-bootstrap")
    )["data"]["bootstrapped"]
    is False
)
bootstrap = json.loads(
    server.succeed(
        "curl -fsS -H 'Content-Type: application/json' -d '{\"password\":\"fixture-actual-password-26\"}' http://127.0.0.1:5006/account/bootstrap"
    )
)
assert bootstrap["status"] == "ok", bootstrap
assert (
    json.loads(
        server.succeed("curl -fsS http://127.0.0.1:5006/account/needs-bootstrap")
    )["data"]["bootstrapped"]
    is True
)

# Header login is forbidden even when the caller is local and supplies the
# correct password in the header.
server.fail(
    "curl -fsS -H 'Content-Type: application/json' -H 'x-actual-password: fixture-actual-password-26' -d '{}' http://127.0.0.1:5006/account/login"
)
login = json.loads(
    server.succeed(
        "curl -fsS -H 'Content-Type: application/json' -d '{\"password\":\"fixture-actual-password-26\"}' http://127.0.0.1:5006/account/login"
    )
)
assert login["status"] == "ok", login
assert login["data"]["token"], login

server.succeed("systemctl restart actual.service")
server.wait_until_succeeds("curl -fsS http://127.0.0.1:5006/health")
login = json.loads(
    server.succeed(
        "curl -fsS -H 'Content-Type: application/json' -d '{\"password\":\"fixture-actual-password-26\"}' http://127.0.0.1:5006/account/login"
    )
)
assert login["status"] == "ok", login
assert login["data"]["token"], login
server.succeed("test -e /var/lib/actual/server-files/account.sqlite")
server.succeed("test $(stat -Lc %a /var/lib/actual) = 700")
server.succeed("test -d /var/lib/private/actual")

# A stopped-service copy must preserve the account database and login.
server.succeed("systemctl stop actual.service")
server.succeed(
    "mkdir -p /tmp/actual-restore; cp -aL /var/lib/actual/. /tmp/actual-restore/"
)
server.succeed("rm /var/lib/actual/server-files/account.sqlite")
server.succeed("cp -a /tmp/actual-restore/. /var/lib/actual/")
server.succeed("systemctl start actual.service")
server.wait_until_succeeds("curl -fsS http://127.0.0.1:5006/health")
restored = json.loads(
    server.succeed(
        "curl -fsS -H 'Content-Type: application/json' -d '{\"password\":\"fixture-actual-password-26\"}' http://127.0.0.1:5006/account/login"
    )
)
assert restored["status"] == "ok", restored
assert restored["data"]["token"], restored
