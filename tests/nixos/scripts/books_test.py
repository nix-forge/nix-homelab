"""Exercise books with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable

    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)
    start_all: Callable[[], None] = cast("Callable[[], None]", None)

from datetime import timedelta

start_all()
machine.wait_for_unit("komga.service")
machine.wait_for_open_port(25600)
machine.succeed("python /etc/books_runtime.py seed")
machine.wait_until_succeeds("curl -fsS http://127.0.0.1:25600/api/v1/claim")
machine.succeed("python /etc/books_runtime.py setup", timeout=timedelta(seconds=180))
# Exercise the actual service mount namespace, not only Unix mode bits.
machine.succeed(
    "nsenter --target $(systemctl show -p MainPID --value komga) --mount test -r '/srv/media/library/books/Public series/Public book.cbz'"
)
machine.fail(
    "nsenter --target $(systemctl show -p MainPID --value komga) --mount touch /srv/media/library/books/forbidden"
)
machine.succeed("systemctl restart komga")
machine.wait_for_open_port(25600)
machine.wait_until_succeeds(
    "python /etc/books_runtime.py verify", timeout=timedelta(seconds=90)
)
