"""Exercise native BookOrbit startup, read-only media and PG18 state restoration."""

import json
import shlex
from datetime import timedelta
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable

    from test_driver.machine import QemuMachine

    machine: QemuMachine = cast("QemuMachine", None)
    start_all: Callable[[], None] = cast("Callable[[], None]", None)


# Uses the real endpoints already called by bootstrap_bookorbit.py. No BookOrbit
# HTTP adapter, application executable, migration executable or database is faked.


def api(mode):
    return machine.succeed(
        "python3 /etc/bookorbit_native_runtime.py " + shlex.quote(mode)
    )


def psql(sql):
    return machine.succeed(
        "runuser -u bookorbit -- psql -X -v ON_ERROR_STOP=1 -At "
        "-h /run/bookorbit-postgres -U bookorbit -d bookorbit -c " + shlex.quote(sql)
    ).strip()


def assert_read_only_media():
    machine.succeed(
        "set -eu; pid=$(systemctl show bookorbit -p MainPID --value); "
        'nsenter -t "$pid" -m -- findmnt -no OPTIONS -T /books | grep -Eq "(^|,)ro(,|$)"; '
        'nsenter -t "$pid" -m -- runuser -u bookorbit -- test -r /books/books; '
        '! nsenter -t "$pid" -m -- runuser -u bookorbit -- touch /books/books/forbidden'
    )


start_all()
machine.wait_for_unit("multi-user.target")
machine.succeed("systemctl start fixture-secrets homelab-storage fixture-readers")
machine.succeed("test ! -e /var/lib/bookorbit/postgres/native/PG_VERSION")
machine.fail("systemctl start bookorbit-native-db")
machine.succeed("systemctl stop bookorbit-native-db")
machine.succeed("test ! -e /var/lib/bookorbit/postgres/native/PG_VERSION")
machine.succeed("systemctl reset-failed bookorbit-native-db")
machine.succeed("systemctl start fixture-initdb")
machine.succeed("systemctl start bookorbit bookorbit-metadata-policy")
machine.wait_for_unit("bookorbit-native-db.service")
machine.wait_for_unit("bookorbit.service")
machine.succeed("test $(cat /var/lib/bookorbit/postgres/native/PG_VERSION) = 18")
machine.succeed("test $(systemctl show bookorbit-migrate -p Result --value) = success")
machine.succeed(
    "test $(systemctl show bookorbit-migrate -p ExecMainStatus --value) = 0"
)
machine.succeed("test -f /run/bookorbit-metadata/ready")
api("inventory")

assert psql("SHOW server_version_num;").startswith("18")
assert not psql("SHOW listen_addresses;")
machine.succeed(
    'set -eu; listeners=$(ss -lntH "( sport = :5432 )"); test -z "$listeners"'
)
machine.succeed("test $(stat -c %U:%G /run/bookorbit-postgres) = bookorbit:bookorbit")
machine.succeed("test $(stat -c %a /run/bookorbit-postgres) = 700")

# The HTTP endpoint has no readiness notification; the driver uses bounded,
# positive-interval retries against the real service after unit startup.
machine.wait_until_succeeds(
    "python3 /etc/bookorbit_native_runtime.py health", timeout=timedelta(seconds=180)
)
api("setup")
created = json.loads(api("create"))

# Verify the real mount namespace and credential ownership. A host-level write
# permission check alone cannot establish the generated read-only /books bind.
assert_read_only_media()
machine.succeed("test ! -e /srv/bookorbit-fixture/library/books/forbidden")
machine.succeed("test $(stat -c %U:%G /var/lib/bookorbit/data) = bookorbit:bookorbit")
machine.succeed("test $(stat -c %a /var/lib/bookorbit/data) = 700")
machine.succeed(
    "set -eu; for name in jwt-secret setup-token request-key podcast-key; do "
    "test $(stat -c %U:%G /run/bookorbit-secrets/$name) = bookorbit:bookorbit; "
    "test $(stat -c %a /run/bookorbit-secrets/$name) = 400; "
    "cmp /run/bookorbit-fixture/$name /run/bookorbit-secrets/$name; done"
)
machine.succeed("systemctl restart bookorbit")
machine.wait_for_unit("bookorbit.service")
machine.wait_until_succeeds(
    "python3 /etc/bookorbit_native_runtime.py verify", timeout=timedelta(seconds=180)
)
assert json.loads(api("verify")) == created

# The only destructive actions below affect this disposable VM. Stop all local
# application writers before snapshot/replacement; leave PG18 up for logical IO.
machine.succeed(
    "systemctl stop bookorbit-bootstrap bookorbit-metadata-policy bookorbit"
)
machine.succeed("! systemctl is-active --quiet bookorbit")
machine.succeed("install -d -m 0700 /var/lib/bookorbit-restore-fixture")
machine.succeed(
    "set -eu; umask 077; runuser -u bookorbit -- pg_dump --format=custom "
    "-h /run/bookorbit-postgres -U bookorbit -d bookorbit "
    "> /var/lib/bookorbit-restore-fixture/database.dump; "
    "cp -a /var/lib/bookorbit/data /var/lib/bookorbit-restore-fixture/data; "
    "sha256sum /run/bookorbit-fixture/* > /var/lib/bookorbit-restore-fixture/credentials.sha256"
)
machine.succeed("test -s /var/lib/bookorbit-restore-fixture/database.dump")
machine.succeed(
    "test $(stat -c %U:%G:%a /var/lib/bookorbit-restore-fixture/database.dump) = root:root:600"
)
machine.succeed(
    "test $(stat -c %U:%G:%a /var/lib/bookorbit-restore-fixture/data) = bookorbit:bookorbit:700"
)
machine.succeed(
    "set -eu; runuser -u bookorbit -- dropdb -h /run/bookorbit-postgres -U bookorbit bookorbit; "
    "runuser -u bookorbit -- createdb -h /run/bookorbit-postgres -U bookorbit bookorbit"
)
assert (
    psql("SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")
    == "0"
)
machine.succeed(
    "runuser -u bookorbit -- pg_restore --exit-on-error --single-transaction "
    "-h /run/bookorbit-postgres -U bookorbit -d bookorbit "
    "< /var/lib/bookorbit-restore-fixture/database.dump"
)
machine.succeed(
    "set -eu; rm -rf /var/lib/bookorbit/data; "
    "cp -a /var/lib/bookorbit-restore-fixture/data /var/lib/bookorbit/data; "
    "sha256sum -c /var/lib/bookorbit-restore-fixture/credentials.sha256"
)
machine.succeed("systemctl start bookorbit bookorbit-metadata-policy")
machine.wait_for_unit("bookorbit.service")
machine.wait_until_succeeds(
    "python3 /etc/bookorbit_native_runtime.py verify", timeout=timedelta(seconds=180)
)
assert json.loads(api("verify")) == created
machine.succeed(
    "test $(stat -c %U:%G:%a /var/lib/bookorbit/data) = bookorbit:bookorbit:700"
)
assert_read_only_media()
machine.succeed("test $(systemctl show bookorbit-migrate -p Result --value) = success")
machine.succeed("test ! -e /run/bookorbit-bootstrap/ready")
