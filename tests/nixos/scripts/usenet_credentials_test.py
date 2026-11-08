"""Exercise usenet credentials with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

import json

machine.wait_for_unit("nzbget.service")
machine.wait_for_unit("sabnzbd.service")
machine.wait_until_succeeds(
    "curl -sf -u operator:public-original-password http://127.0.0.1:6789/jsonrpc/version"
)
machine.fail("curl -sf -u nzbget:tegbzn6789 http://127.0.0.1:6789/jsonrpc/version")
machine.wait_until_succeeds(
    "curl -sf 'http://127.0.0.1:8080/api?mode=version&output=json&apikey=public-sab-fixture-api-key'"
)
response = json.loads(
    machine.succeed(
        "curl -sf 'http://127.0.0.1:8080/api?mode=get_config&section=categories&output=json&apikey=public-sab-fixture-api-key'"
    )
)
assert {item["name"] for item in response["config"]["categories"]} >= {
    "sonarr",
    "radarr",
    "lidarr",
}, response
machine.succeed(
    "printf '%s\\n' 'ControlUsername=operator' 'ControlPassword=public-rotated-password' > /run/nix-seal/system/secrets/nzbget-credentials.conf; systemctl restart nzbget"
)
machine.wait_until_succeeds(
    "curl -sf -u operator:public-rotated-password http://127.0.0.1:6789/jsonrpc/version"
)
machine.fail(
    "curl -sf -u operator:public-original-password http://127.0.0.1:6789/jsonrpc/version"
)
machine.succeed("test $(stat -c %a /var/lib/nzbget/nzbget.conf) = 600")
machine.succeed("systemctl restart sabnzbd")
machine.wait_until_succeeds(
    "curl -sf 'http://127.0.0.1:8080/api?mode=version&output=json&apikey=public-sab-fixture-api-key'"
)
