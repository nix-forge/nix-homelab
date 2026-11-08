"""Exercise declared indexer files and hostile service-owned paths."""

import runpy
import stat
from pathlib import Path

import pytest

INSTALL = runpy.run_path(
    str(Path(__file__).parents[2] / "scripts/indexers/install_definitions.py")
)["install"]


def test_replaces_declared_file_preserving_unmanaged_files(tmp_path: Path) -> None:
    state = tmp_path / "state"
    destination = state / "Definitions/Custom"
    destination.mkdir(parents=True)
    source = tmp_path / "store/source.yml"
    source.parent.mkdir(exist_ok=True)
    source.write_text("id: fixture\n")
    target = destination / "example.yml"
    target.write_text("old")
    target.chmod(0o444)
    unmanaged = destination / "unmanaged.yml"
    unmanaged.write_text("keep")
    INSTALL(state, {"example.yml": str(source)}, tmp_path / "store")
    assert target.read_text() == "id: fixture\n"
    assert stat.S_IMODE(target.stat().st_mode) == 0o644
    assert unmanaged.read_text() == "keep"
    assert not list(destination.glob(".homelab-*"))


@pytest.mark.parametrize("component", ["Definitions", "Definitions/Custom"])
def test_refuses_linked_parent_without_changing_victim(
    tmp_path: Path, component: str
) -> None:
    state = tmp_path / "state"
    state.mkdir()
    link = state / component
    link.parent.mkdir(exist_ok=True)
    victim = tmp_path / "victim"
    victim.mkdir(mode=0o700)
    link.symlink_to(victim, target_is_directory=True)
    source = tmp_path / "store/source.yml"
    source.parent.mkdir(exist_ok=True)
    source.write_text("public")
    with pytest.raises(OSError, match=r"Too many levels|Not a directory"):
        INSTALL(state, {"example.yml": str(source)}, tmp_path / "store")
    assert list(victim.iterdir()) == []
    assert stat.S_IMODE(victim.stat().st_mode) == 0o700


def test_replaces_linked_leaf_without_changing_target(tmp_path: Path) -> None:
    state = tmp_path / "state"
    destination = state / "Definitions/Custom"
    destination.mkdir(parents=True)
    victim = tmp_path / "victim.yml"
    victim.write_text("private")
    (destination / "example.yml").symlink_to(victim)
    source = tmp_path / "store/source.yml"
    source.parent.mkdir(exist_ok=True)
    source.write_text("public")
    INSTALL(state, {"example.yml": str(source)}, tmp_path / "store")
    assert victim.read_text() == "private"
    assert (destination / "example.yml").read_text() == "public"


def test_failed_copy_preserves_previous_definition(tmp_path: Path) -> None:
    state = tmp_path / "state"
    destination = state / "Definitions/Custom"
    destination.mkdir(parents=True)
    target = destination / "example.yml"
    target.write_text("previous")
    with pytest.raises(FileNotFoundError):
        INSTALL(
            state, {"example.yml": str(tmp_path / "store/missing")}, tmp_path / "store"
        )
    assert target.read_text() == "previous"
    assert not list(destination.glob(".homelab-*"))


@pytest.mark.parametrize("link_inside_store", [False, True])
def test_refuses_sources_outside_immutable_store(
    tmp_path: Path, link_inside_store: bool
) -> None:
    state = tmp_path / "state"
    state.mkdir()
    store = tmp_path / "store"
    store.mkdir()
    private = tmp_path / "private.yml"
    private.write_text("private")
    source = private
    if link_inside_store:
        source = store / "escape.yml"
        source.symlink_to(private)
    with pytest.raises(ValueError, match="immutable store"):
        INSTALL(state, {"example.yml": str(source)}, store)
    assert not (state / "Definitions/Custom/example.yml").exists()
    assert private.read_text() == "private"
