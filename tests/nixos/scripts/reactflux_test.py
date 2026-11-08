"""Exercise reactflux with the NixOS test driver."""

import json
import shlex
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    command: str = cast("str", None)
    machine: QemuMachine = cast("QemuMachine", None)
    user: dict[str, object] = cast("dict[str, object]", None)

machine.wait_for_unit("nginx.service")
machine.wait_for_open_port(18082)
machine.succeed("ss -ltn | grep -q '127.0.0.1:18082'")
machine.fail("ss -ltn | grep -q '0.0.0.0:18082'")
root = "http://127.0.0.1:18082"
html = machine.succeed("curl --fail --silent " + root)
assert "ReactFlux" in html
assert '<script type="module"' in html
assert "ReactFlux" in machine.succeed("curl --fail --silent " + root + "/login")
machine.fail("curl --fail --silent " + root + "/assets/missing.js")
manifest = json.loads(
    machine.succeed("curl --fail --silent " + root + "/manifest.webmanifest")
)
assert manifest["display"] == "standalone"
headers = machine.succeed("curl -sSI " + root)
assert "script-src 'self'" in headers
assert "frame-ancestors 'none'" in headers
assert "no-referrer" in headers
assert "no-cache" in machine.succeed("curl -sSI " + root + "/sw.js")
machine.fail("curl --fail --silent " + root + "/v1/me")
machine.fail("curl --fail --silent -u admin:wrong " + root + "/v1/me")
current_user = json.loads(machine.succeed(command + " " + root + "/v1/me"))
assert current_user["id"] == user["id"]
headers = machine.succeed(command + " -I " + root + "/v1/me")
assert "no-store" in headers
# The frontend password exchange uses the real upstream API, not a mock.
key = json.loads(
    machine.succeed(
        command
        + " -H 'Content-Type: application/json' -d '{\"description\":\"Fixture frontend\"}' "
        + root
        + "/v1/api-keys"
    )
)
token_command = "curl --fail --silent -H 'X-Auth-Token: " + key["token"] + "' "
assert json.loads(machine.succeed(token_command + root + "/v1/me"))["id"] == user["id"]
machine.succeed(command + " -X DELETE " + root + "/v1/api-keys/" + str(key["id"]))
machine.fail(token_command + root + "/v1/me")
machine.wait_for_unit("fixture-unsafe-feed.service")
machine.wait_for_open_port(19000, timeout=30)
categories = json.loads(machine.succeed(command + " " + root + "/v1/categories"))
payload = json.dumps({
    "feed_url": "http://127.0.0.1:19000/feed.xml",
    "category_id": categories[0]["id"],
})
feed = json.loads(
    machine.succeed(
        command
        + " -H 'Content-Type: application/json' -d "
        + shlex.quote(payload)
        + " "
        + root
        + "/v1/feeds"
    )
)
article = json.loads(
    machine.succeed(
        command + " " + root + "/v1/feeds/" + str(feed["feed_id"]) + "/entries"
    )
)["entries"][0]
new_feed = json.loads(
    machine.succeed(command + " " + root + "/v1/feeds/" + str(feed["feed_id"]))
)
icon_id = new_feed["icon"]["external_icon_id"]
icon_headers = machine.succeed(
    "curl --fail --silent -I " + root + "/feed-icon/" + icon_id
)
assert "image/png" in icon_headers
assert "photo.jpg" in article["content"]
assert "<script" not in article["content"]
assert "onerror" not in article["content"]
assert "javascript:" not in article["content"]
machine.succeed("systemctl restart nginx.service")
machine.wait_for_open_port(18082)
machine.succeed(command + " " + root + "/v1/me")
