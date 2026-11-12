"""Behavior checks for managed Homebridge plugin links."""

import grp
import importlib.util
import json
import os
import pwd
from pathlib import Path

import pytest

SOURCE = Path(__file__).parents[2] / "modules/iot/scripts/homebridge_plugins.py"
spec = importlib.util.spec_from_file_location("homebridge_plugins", SOURCE)
assert spec is not None
assert spec.loader is not None
plugins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugins)


def test_managed_links_update_and_prune_without_touching_ui_plugins(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Removing a declaration prunes its old link and preserves mutable plugins."""
    plugin_path = tmp_path / "node_modules"
    plugin_path.mkdir()
    old_source = tmp_path / "old"
    new_source = tmp_path / "new"
    old_source.mkdir()
    new_source.mkdir()
    ui_plugin = plugin_path / "homebridge-ui-managed"
    ui_plugin.mkdir()
    desired = {"homebridge-managed": str(old_source)}
    monkeypatch.setattr(plugins, "read_manifest", lambda _: desired.copy())
    user = pwd.getpwuid(os.getuid()).pw_name
    group = grp.getgrgid(os.getgid()).gr_name

    plugins.reconcile(tmp_path / "manifest", plugin_path, user, group)
    link = plugin_path / "homebridge-managed"
    assert link.is_symlink()
    assert link.readlink() == old_source
    assert ui_plugin.is_dir()

    desired["homebridge-managed"] = str(new_source)
    plugins.reconcile(tmp_path / "manifest", plugin_path, user, group)
    assert link.readlink() == new_source

    desired.clear()
    plugins.reconcile(tmp_path / "manifest", plugin_path, user, group)
    assert not link.exists()
    assert ui_plugin.is_dir()
    assert json.loads((plugin_path / plugins.LEDGER).read_text())["managed"] == {}


def test_modified_link_is_not_removed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A link changed through the UI is no longer assumed to be owned by Nix."""
    plugin_path = tmp_path / "node_modules"
    source = tmp_path / "source"
    alternate = tmp_path / "alternate"
    source.mkdir()
    alternate.mkdir()
    desired = {"homebridge-managed": str(source)}
    monkeypatch.setattr(plugins, "read_manifest", lambda _: desired.copy())
    user = pwd.getpwuid(os.getuid()).pw_name
    group = grp.getgrgid(os.getgid()).gr_name
    plugins.reconcile(tmp_path / "manifest", plugin_path, user, group)

    link = plugin_path / "homebridge-managed"
    link.unlink()
    link.symlink_to(alternate, target_is_directory=True)
    desired.clear()
    plugins.reconcile(tmp_path / "manifest", plugin_path, user, group)
    assert link.is_symlink()
    assert link.readlink() == alternate


def test_modified_link_is_not_overwritten(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A plugin link changed outside Nix requires an explicit cleanup decision."""
    plugin_path = tmp_path / "node_modules"
    source = tmp_path / "source"
    alternate = tmp_path / "alternate"
    source.mkdir()
    alternate.mkdir()
    desired = {"homebridge-managed": str(source)}
    monkeypatch.setattr(plugins, "read_manifest", lambda _: desired.copy())
    user = pwd.getpwuid(os.getuid()).pw_name
    group = grp.getgrgid(os.getgid()).gr_name
    plugins.reconcile(tmp_path / "manifest", plugin_path, user, group)

    link = plugin_path / "homebridge-managed"
    link.unlink()
    link.symlink_to(alternate, target_is_directory=True)
    with pytest.raises(ValueError, match="changed outside Nix"):
        plugins.reconcile(tmp_path / "manifest", plugin_path, user, group)
    assert link.readlink() == alternate


def test_scoped_cleanup_rejects_symlinked_parent(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A stale ledger cannot direct cleanup through a redirected npm scope."""
    plugin_path = tmp_path / "node_modules"
    plugin_path.mkdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "homebridge-managed").symlink_to(tmp_path / "source")
    (plugin_path / "@scope").symlink_to(outside, target_is_directory=True)
    (plugin_path / plugins.LEDGER).write_text(
        json.dumps({
            "schema": 1,
            "managed": {"@scope/homebridge-managed": str(tmp_path / "source")},
        })
    )
    monkeypatch.setattr(plugins, "read_manifest", lambda _: {})
    user = pwd.getpwuid(os.getuid()).pw_name
    group = grp.getgrgid(os.getgid()).gr_name

    with pytest.raises(ValueError, match="scope must not be a symlink"):
        plugins.reconcile(tmp_path / "manifest", plugin_path, user, group)
    assert (outside / "homebridge-managed").is_symlink()


def test_manifest_rejects_non_store_source(tmp_path: Path) -> None:
    """Only package artifacts may become Nix-owned plugin links."""
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps([
            {"name": "homebridge-example", "source": str(tmp_path / "mutable")}
        ])
    )
    with pytest.raises(ValueError, match="Invalid Homebridge plugin manifest"):
        plugins.read_manifest(manifest)
