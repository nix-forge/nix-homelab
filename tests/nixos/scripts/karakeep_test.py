"""Exercise karakeep with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

import json

machine.start()
machine.wait_for_unit("homelab-karakeep-secrets.service")
machine.wait_for_unit("meilisearch.service")
machine.wait_for_unit("karakeep-browser.service")
machine.wait_for_unit("karakeep-workers.service")
machine.wait_for_unit("karakeep-web.service")
machine.wait_for_open_port(15337)
machine.wait_for_open_port(19222)

health = json.loads(
    machine.succeed("curl --fail --silent http://127.0.0.1:15337/api/health")
)
assert health == {"status": "ok"}
machine.succeed("ss --listening --tcp --numeric | grep -q '127.0.0.1:15337'")
machine.succeed("ss --listening --tcp --numeric | grep -q '127.0.0.1:19222'")
machine.succeed("nc -z -w 1 127.0.0.1 19222")
machine.fail("runuser -u nobody -- nc -z -w 1 127.0.0.1 19222")
machine.fail("systemctl cat karakeep-browser.service | grep -q -- --no-sandbox")
browser_properties = machine.succeed(
    "systemctl show karakeep-browser.service -p User -p NoNewPrivileges -p PrivateUsers -p RestrictNamespaces"
)
assert "User=karakeep-browser" in browser_properties
assert "NoNewPrivileges=yes" in browser_properties
assert "PrivateUsers=no" in browser_properties
assert "RestrictNamespaces=no" in browser_properties
machine.fail("curl --fail --silent http://127.0.0.1:7700/keys")
machine.succeed(
    'curl --fail --silent --header "Authorization: Bearer $(cat /var/lib/karakeep/meili-master-key)" '
    "http://127.0.0.1:7700/keys >/dev/null"
)

machine.succeed("test $(stat --format=%a /var/lib/karakeep/settings.env) = 400")
machine.succeed("test $(stat --format=%a /var/lib/karakeep/meili-master-key) = 400")
machine.succeed("test $(stat --format=%a /var/lib/karakeep/nextauth-secret) = 400")
original = machine.succeed("cat /var/lib/karakeep/nextauth-secret")

properties = machine.succeed(
    "systemctl show karakeep-web.service "
    "-p User -p NoNewPrivileges -p ProtectSystem -p ProtectHome "
    "-p MemoryMax -p TasksMax"
)
assert "User=karakeep" in properties
assert "NoNewPrivileges=yes" in properties
assert "ProtectSystem=strict" in properties
assert "ProtectHome=yes" in properties
assert "MemoryMax=2147483648" in properties
assert "TasksMax=512" in properties

machine.succeed("systemctl restart karakeep-web.service")
machine.wait_for_open_port(15337)
assert machine.succeed("cat /var/lib/karakeep/nextauth-secret") == original

# The unauthenticated DevTools endpoint must never outlive its UID firewall.
browser_pid = machine.succeed(
    "systemctl show karakeep-browser.service -p MainPID --value"
)
machine.succeed("systemctl reload nftables.service")
assert (
    machine.succeed("systemctl show karakeep-browser.service -p MainPID --value")
    == browser_pid
)
machine.succeed("nc -z -w 1 127.0.0.1 19222")
machine.fail("runuser -u nobody -- nc -z -w 1 127.0.0.1 19222")

machine.succeed("systemctl restart nftables.service")
machine.wait_for_unit("karakeep-browser.service")
machine.wait_for_open_port(19222)
machine.fail("runuser -u nobody -- nc -z -w 1 127.0.0.1 19222")

machine.succeed("systemctl stop nftables.service")
machine.fail("systemctl is-active --quiet karakeep-browser.service")
machine.fail("nc -z -w 1 127.0.0.1 19222")
machine.fail("runuser -u nobody -- nc -z -w 1 127.0.0.1 19222")

machine.succeed("systemctl start karakeep-browser.service")
machine.wait_for_unit("nftables.service")
machine.wait_for_open_port(19222)
machine.fail("runuser -u nobody -- nc -z -w 1 127.0.0.1 19222")

machine.succeed("systemctl stop nftables.service")
machine.succeed(
    "mkdir -p /run/systemd/system/nftables.service.d; "
    "printf '[Service]\\nExecStartPre=/run/current-system/sw/bin/false\\n' "
    "> /run/systemd/system/nftables.service.d/test-failure.conf; "
    "systemctl daemon-reload"
)
machine.fail("systemctl start karakeep-browser.service")
machine.fail("systemctl is-active --quiet karakeep-browser.service")
machine.fail("nc -z -w 1 127.0.0.1 19222")
machine.succeed(
    "rm /run/systemd/system/nftables.service.d/test-failure.conf; "
    "systemctl daemon-reload; systemctl reset-failed; "
    "systemctl start karakeep-browser.service"
)
machine.wait_for_open_port(19222)
machine.fail("runuser -u nobody -- nc -z -w 1 127.0.0.1 19222")
