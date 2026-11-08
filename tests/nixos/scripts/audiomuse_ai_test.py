"""Exercise audiomuse ai with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

machine.wait_for_unit("postgresql.service")
machine.wait_for_unit("audiomuse-ai.service")
machine.succeed("curl -fsS http://127.0.0.1:18000/api/health/ready")
machine.succeed(
    "runuser -u audiomuse -- psql -U audiomusedb -d audiomusedb -Atc 'select current_user' | grep -qx audiomusedb"
)
machine.succeed(
    "test -d /var/lib/audiomuse-ai -a -d /var/cache/audiomuse-ai -a -d /run/audiomuse-ai"
)
for role in (
    "flask",
    "queue-worker-high",
    "queue-worker-default",
    "queue-maintenance",
    "config-restart-listener",
):
    machine.succeed(
        "supervisorctl -s unix:///run/audiomuse-ai/supervisor.sock "
        f"status {role} | grep -q RUNNING"
    )
properties = machine.succeed(
    "systemctl show audiomuse-ai.service "
    "-p User -p NoNewPrivileges -p ProtectSystem -p RestrictNamespaces "
    "-p MemoryMax -p TasksMax"
)
assert "User=audiomuse" in properties
assert "NoNewPrivileges=yes" in properties
assert "ProtectSystem=strict" in properties
assert "RestrictNamespaces=yes" in properties
assert "MemoryMax=1073741824" in properties
assert "TasksMax=128" in properties
machine.succeed("systemctl restart audiomuse-ai.service")
machine.wait_until_succeeds("curl -fsS http://127.0.0.1:18000/api/health/ready")
