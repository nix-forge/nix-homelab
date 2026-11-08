"""Exercise miniflux with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

import json
import re
import shlex

machine.start()
machine.wait_for_unit("fixture-feed.service")
machine.wait_for_unit("homelab-miniflux-credentials.service")
machine.wait_for_unit("postgresql.service")
machine.wait_for_unit("miniflux.service")
machine.succeed(
    "systemctl show --property=Result --value homelab-miniflux-bootstrap.service | grep -qx success"
)
machine.wait_for_open_port(18080)

machine.succeed("curl --fail --silent http://127.0.0.1:18080/healthcheck")
machine.succeed("ss --listening --tcp --numeric | grep -q '127.0.0.1:18080'")
machine.fail("ss --listening --tcp --numeric | grep -q '0.0.0.0:18080'")
machine.succeed("test $(stat --format=%a /var/lib/homelab-miniflux) = 700")
machine.succeed("test $(stat --format=%a /var/lib/homelab-miniflux/admin.env) = 400")
machine.wait_until_succeeds("test -f /var/lib/homelab-miniflux/initial-feeds-imported")

auth = "$(sed -n 's/^ADMIN_PASSWORD=//p' /var/lib/homelab-miniflux/admin.env)"
command = "curl --fail --silent -u admin:" + auth
user = json.loads(machine.succeed(command + " http://127.0.0.1:18080/v1/me"))
assert user["entry_sorting_direction"] == "desc"
assert user["entries_per_page"] == 30
feeds = json.loads(machine.succeed(command + " http://127.0.0.1:18080/v1/feeds"))
assert len(feeds) == 1
assert feeds[0]["feed_url"] == "http://127.0.0.1:18999/feed.xml"
assert feeds[0]["category"]["title"] == "Fixture reporting"
machine.fail("curl --fail --silent -u admin:wrong http://127.0.0.1:18080/v1/feeds")

inventory = json.loads(machine.succeed("cat /etc/homelab/state-inventory.json"))
assert inventory["miniflux"]["paths"] == ["/var/lib/homelab-miniflux"]
database = json.loads(machine.succeed("cat /etc/homelab/database-exports.json"))
assert database["miniflux"]["database"] == "miniflux"
machine.succeed(
    "runuser -u postgres -- psql -Atqc \"SELECT 1 FROM pg_database WHERE datname='miniflux'\" | grep -qx 1"
)

machine.succeed("systemctl start homelab-miniflux-content-upgrade.service")
entries = json.loads(machine.succeed(command + " http://127.0.0.1:18080/v1/entries"))[
    "entries"
]
assert len(entries) == 1
entry = entries[0]
assert entry["content"].count("Evidence from original reporting.") == 80
assert "<figcaption>Publisher credit</figcaption>" in entry["content"]
assert "<img " in entry["content"]
assert feeds[0]["crawler"] is True
machine.succeed(
    command
    + " -X PUT -H 'Content-Type: application/json' --data '{\"content\":\"A short summary.\"}' http://127.0.0.1:18080/v1/entries/"
    + str(entry["id"])
)
machine.succeed(
    command
    + " -X PUT http://127.0.0.1:18080/v1/entries/"
    + str(entry["id"])
    + "/bookmark"
)
machine.succeed(
    "rm /var/lib/homelab-miniflux/content-upgrade-fixture-v1.json; systemctl restart homelab-miniflux-content-upgrade.service"
)
repaired = json.loads(
    machine.succeed(command + " http://127.0.0.1:18080/v1/entries/" + str(entry["id"]))
)
assert repaired["content"].count("Evidence from original reporting.") == 80
assert repaired["status"] == "unread"
assert repaired["starred"] is True
image_match = re.search(r'<img[^>]+src="([^"]+)"', repaired["content"])
assert image_match is not None
image_url = image_match[1]
machine.succeed("curl --fail --silent " + shlex.quote(image_url) + " > /tmp/image.png")
raw_content = machine.succeed(
    "runuser -u postgres -- psql -d miniflux -Atc 'SELECT content FROM entries'"
)
assert "/proxy/" not in raw_content, (
    "Store original publisher URLs, never display proxy URLs"
)
assert "photo.webp" in raw_content
user = json.loads(machine.succeed(command + " http://127.0.0.1:18080/v1/me"))
assert user["stylesheet"] == "body { line-height: 1.7; }"
machine.succeed(
    command
    + " -X PUT -H 'Content-Type: application/json' --data '{\"crawler\":false}' http://127.0.0.1:18080/v1/feeds/"
    + str(feeds[0]["id"])
)
machine.succeed("systemctl restart homelab-miniflux-content-upgrade.service")
unchanged = json.loads(
    machine.succeed(command + " http://127.0.0.1:18080/v1/feeds/" + str(feeds[0]["id"]))
)
assert unchanged["crawler"] is False, "Completed upgrades must preserve UI preferences"

original = machine.succeed("cat /var/lib/homelab-miniflux/admin.env")
machine.succeed(
    command + " -X DELETE http://127.0.0.1:18080/v1/feeds/" + str(feeds[0]["id"])
)
machine.succeed("systemctl restart miniflux.service homelab-miniflux-bootstrap.service")
machine.wait_for_open_port(18080)
assert machine.succeed("cat /var/lib/homelab-miniflux/admin.env") == original
feeds = json.loads(machine.succeed(command + " http://127.0.0.1:18080/v1/feeds"))
assert feeds == [], "A user's feed deletion must survive a service restart"
