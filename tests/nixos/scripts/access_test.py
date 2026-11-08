"""Exercise access with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable

    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    client: QemuMachine = cast("QemuMachine", None)
    server: QemuMachine = cast("QemuMachine", None)
    start_all: Callable[[], None] = cast("Callable[[], None]", None)

start_all()
server.wait_for_unit("authelia-homelab.service")
server.wait_for_unit("caddy.service")
server.wait_for_unit("dashboard-fixture.service")
client.wait_until_succeeds("curl -kfsS https://auth.homelab.home.arpa/api/health")
client.succeed(
    "test $(curl -ks -o /dev/null -w '%{http_code}' https://dashboard.homelab.home.arpa/) = 302"
)
client.succeed(
    "test $(curl -ks -H 'Remote-User: fixture' -H 'Remote-Groups: media' -H 'X-Forwarded-User: fixture' -o /dev/null -w '%{http_code}' https://dashboard.homelab.home.arpa/) = 302"
)
client.fail("curl -fsS --connect-timeout 2 http://192.168.1.10:8082/")
client.fail("curl -fsS --connect-timeout 2 http://192.168.1.10:9091/api/health")
server.fail("curl -fsS --connect-timeout 2 http://127.0.0.1:2019/config/")
client.succeed(
    'curl -kfSs -c /tmp/session -H \'Content-Type: application/json\' -d \'{"username":"fixture","password":"disposable-password","keepMeLoggedIn":false,"targetURL":"https://dashboard.homelab.home.arpa/","requestMethod":"GET"}\' https://auth.homelab.home.arpa/api/firstfactor'
)
client.succeed(
    "curl -kfSs -b /tmp/session https://dashboard.homelab.home.arpa/ | grep -F 'protected fixture'"
)
server.succeed("systemctl stop nftables")
server.fail("systemctl is-active dashboard-fixture")
client.fail("curl -fsS --connect-timeout 2 http://192.168.1.10:8082/")
server.succeed(
    "systemctl start nftables; systemctl start authelia-homelab dashboard-fixture caddy"
)
# Memory-backed sessions must not survive an identity service restart.
server.succeed("systemctl restart authelia-homelab")
server.wait_for_unit("authelia-homelab.service")
client.wait_until_succeeds(
    "test $(curl -ks -b /tmp/session -o /dev/null -w '%{http_code}' https://dashboard.homelab.home.arpa/) = 302"
)
