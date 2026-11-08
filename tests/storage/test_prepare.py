"""Exercise safe directory ownership without altering host system directories."""

import os
import runpy
import stat
from pathlib import Path

import pytest

MODULE = runpy.run_path(str(Path(__file__).parents[2] / "scripts/storage/prepare.py"))
PREPARE = MODULE["prepare"]


@pytest.mark.parametrize(
    "path",
    [
        "/etc",
        "/etc/media",
        "/usr",
        "/var/lib",
        "/home",
        "/run/credentials/private",
        "/nix/store/media",
    ],
)
def test_system_directories_are_rejected_before_filesystem_access(
    monkeypatch: pytest.MonkeyPatch, path: str
) -> None:
    """Reject privileged locations before opening or changing any directory."""

    def unexpected(*_args, **_kwargs):
        pytest.fail("unsafe path reached a filesystem operation")

    monkeypatch.setattr(MODULE["os"], "open", unexpected)
    with pytest.raises(ValueError, match="system directories"):
        PREPARE(path, os.getgid())


def test_custom_owner_and_private_mode(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Apply the selected service owner while preserving private group access."""
    ownership = []
    monkeypatch.setattr(
        MODULE["os"],
        "fchown",
        lambda _fd, owner, group: ownership.append((owner, group)),
    )
    target = tmp_path / "downloads" / "complete"
    PREPARE(str(target), os.getgid(), owner=os.getuid(), mode=0o770)
    assert ownership == [(os.getuid(), os.getgid())]
    assert stat.S_IMODE(target.stat().st_mode) == 0o770


def test_service_owned_link_is_not_followed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Do not redirect a privileged preparation job through a writable link."""
    victim = tmp_path / "victim"
    victim.mkdir(mode=0o700)
    link = tmp_path / "downloads"
    link.symlink_to(victim, target_is_directory=True)
    ownership = []
    monkeypatch.setattr(
        MODULE["os"], "fchown", lambda *values: ownership.append(values)
    )
    with pytest.raises(OSError, match=r"Too many levels|Not a directory"):
        PREPARE(str(link), os.getgid())
    assert ownership == []
    assert stat.S_IMODE(victim.stat().st_mode) == 0o700
