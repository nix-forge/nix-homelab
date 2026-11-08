import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[2] / "scripts/media/install_jellyfin_plugins.py"
)
SPEC = importlib.util.spec_from_file_location("install_jellyfin_plugins", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class JellyfinPluginInstallTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.plugins = self.root / "plugins"
        self.first = self.root / "first"
        self.first.mkdir()
        (self.first / "plugin.dll").write_text("first")

    def test_update_removes_old_files_and_preserves_other_plugins(self) -> None:
        unmanaged = self.plugins / "UI plugin"
        unmanaged.mkdir(parents=True)
        (unmanaged / "ui.dll").write_text("untouched")
        installer.install_plugins(self.plugins, {"Managed": str(self.first)})
        old = self.plugins / "Managed" / "plugin.dll"
        self.assertEqual(old.read_text(), "first")
        original_mtime = old.stat().st_mtime_ns
        installer.install_plugins(self.plugins, {"Managed": str(self.first)})
        self.assertEqual(old.stat().st_mtime_ns, original_mtime)

        second = self.root / "second"
        second.mkdir()
        (second / "new.dll").write_text("second")
        installer.install_plugins(self.plugins, {"Managed": str(second)})
        self.assertFalse(old.exists())
        self.assertEqual((self.plugins / "Managed" / "new.dll").read_text(), "second")
        self.assertEqual((unmanaged / "ui.dll").read_text(), "untouched")

    def test_refuses_unmanaged_and_symlink_destinations(self) -> None:
        unmanaged = self.plugins / "UI plugin"
        unmanaged.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "unmanaged"):
            installer.install_plugins(self.plugins, {"UI plugin": str(self.first)})

        external = self.root / "external"
        external.mkdir()
        (self.plugins / "link").symlink_to(external, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            installer.install_plugins(self.plugins, {"link": str(self.first)})
        self.assertEqual(list(external.iterdir()), [])

    def test_adopts_existing_marked_plugin(self) -> None:
        existing = self.plugins / "Managed"
        existing.mkdir(parents=True)
        (existing / ".nix-managed").touch()
        (existing / "stale.dll").write_text("old")
        installer.install_plugins(self.plugins, {"Managed": str(self.first)})
        self.assertFalse((existing / "stale.dll").exists())
        self.assertEqual((existing / "plugin.dll").read_text(), "first")

    def test_rejects_path_traversal(self) -> None:
        with self.assertRaisesRegex(ValueError, "Invalid plugin name"):
            installer.install_plugins(self.plugins, {"../outside": str(self.first)})
        self.assertFalse((self.root / "outside").exists())


if __name__ == "__main__":
    unittest.main()
