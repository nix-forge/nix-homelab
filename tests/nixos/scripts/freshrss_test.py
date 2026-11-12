"""Exercise freshrss with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)


machine.start()
machine.wait_until_succeeds("test -f /var/lib/freshrss/news-starter-imported")
machine.succeed(
    "systemctl show --property=Result --value freshrss-config.service | grep -qx success"
)
machine.succeed(
    "systemctl show --property=Result --value homelab-freshrss-bootstrap.service | grep -qx success"
)
machine.wait_for_open_port(18081)
machine.succeed("curl --fail --silent http://127.0.0.1:18081/ >/dev/null")
machine.succeed(
    "curl --silent --head http://127.0.0.1:18081/ | grep -qi '^Referrer-Policy: no-referrer'"
)
machine.succeed("ss --listening --tcp --numeric | grep -q '127.0.0.1:18081'")
machine.fail("ss --listening --tcp --numeric | grep -q '0.0.0.0:18081'")
machine.succeed("test -f /var/lib/freshrss/users/runtime-reader/config.php")
machine.fail("test -d /var/lib/freshrss/users/ignored-static-name")
machine.succeed("php -l /etc/verify-freshrss-login.php")
machine.succeed(
    "php /etc/verify-freshrss-login.php /var/lib/freshrss/config.php "
    "/var/lib/freshrss/users/runtime-reader/config.php"
)
script = (
    machine
    .succeed("systemctl show --property=ExecStart --value freshrss-config.service")
    .split("path=", 1)[1]
    .split(" ;", 1)[0]
)
generated = machine.succeed("cat " + script)
assert "runtime-reader" not in generated
assert "ignored-static-name" not in generated
assert "--password" not in generated
assert "--user " not in generated
machine.succeed("systemctl restart freshrss-config.service")
assert "runtime-reader" not in machine.succeed(
    "journalctl -u freshrss-config.service --no-pager"
)
package = machine.succeed("cat /etc/fresh-package").strip()
prefix = "runuser -u freshrss -- env DATA_PATH=/var/lib/freshrss " + package + "/cli/"
exported = machine.succeed(prefix + "export-opml-for-user.php --user runtime-reader")
assert "http://127.0.0.1:18999/feed.xml" in exported
assert "Reporting" in exported
settings = machine.succeed(prefix + "reconfigure-user.php --user runtime-reader --list")
assert "default_view=all" in settings
assert "sort_order=DESC" in settings
assert "topline_thumbnail=large" in settings
assert "Today" in settings
assert "This week" in settings
machine.succeed(
    prefix
    + "reconfigure-user.php --user runtime-reader --key default_view --set --value unread"
)
machine.succeed("systemctl restart homelab-freshrss-bootstrap.service")
assert (
    machine.succeed(
        prefix + "reconfigure-user.php --user runtime-reader --key default_view"
    ).strip()
    == "unread"
)
# Refuse accidental replacement, then retain the same database through rename.
machine.succeed(
    "rm /etc/news-test-username; echo renamed-reader > /etc/news-test-username"
)
machine.fail("systemctl restart freshrss-config.service")
machine.fail("test -d /var/lib/freshrss/users/renamed-reader")
machine.succeed(
    "mv /var/lib/freshrss/users/runtime-reader /var/lib/freshrss/users/renamed-reader"
)
machine.succeed(
    "systemctl reset-failed freshrss-config.service; systemctl restart freshrss-config.service"
)
machine.succeed("systemctl restart homelab-freshrss-bootstrap.service")
assert (
    machine.succeed(
        prefix + "reconfigure-user.php --user renamed-reader --key default_view"
    ).strip()
    == "unread"
)
assert "http://127.0.0.1:18999/feed.xml" in machine.succeed(
    prefix + "export-opml-for-user.php --user renamed-reader"
)
