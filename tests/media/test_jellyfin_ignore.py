import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(
    0, str(pathlib.Path(__file__).resolve().parents[2] / "scripts" / "media")
)
import jellyfin_ignore


class IgnoreTest(unittest.TestCase):
    def test_owned_marker_lifecycle_and_manual_preservation(self):
        with tempfile.TemporaryDirectory() as directory:
            mount = pathlib.Path(directory)
            root = mount / "shows"
            empty = root / "Empty"
            manual = root / "Manual"
            empty.mkdir(parents=True)
            manual.mkdir()
            (manual / ".ignore").write_text("specials\n")
            ledger = mount / "state" / "ledger.json"
            with patch.object(jellyfin_ignore.os.path, "ismount", return_value=True):
                jellyfin_ignore.scan(mount, [root], ledger)
                self.assertTrue((empty / ".ignore").exists())
                (empty / "episode.mkv").touch()
                (manual / "episode.mkv").touch()
                jellyfin_ignore.scan(mount, [root], ledger)
            self.assertFalse((empty / ".ignore").exists())
            self.assertEqual((manual / ".ignore").read_text(), "specials\n")

    def test_missing_mount_does_not_touch_media(self):
        with tempfile.TemporaryDirectory() as directory:
            mount = pathlib.Path(directory)
            root = mount / "shows"
            show = root / "Show"
            show.mkdir(parents=True)
            with (
                patch.object(jellyfin_ignore.os.path, "ismount", return_value=False),
                self.assertRaisesRegex(RuntimeError, "unavailable"),
            ):
                jellyfin_ignore.scan(mount, [root], mount / "ledger")
            self.assertFalse((show / ".ignore").exists())

    def test_changed_owned_marker_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            mount = pathlib.Path(directory)
            root = mount / "shows"
            show = root / "Show"
            show.mkdir(parents=True)
            marker = show / ".ignore"
            ledger = mount / "state" / "ledger.json"
            with patch.object(jellyfin_ignore.os.path, "ismount", return_value=True):
                jellyfin_ignore.scan(mount, [root], ledger)
                marker.write_text("manual\n")
                marker.write_text("")
                (show / "episode.mkv").touch()
                jellyfin_ignore.scan(mount, [root], ledger)
            self.assertTrue(marker.exists())


if __name__ == "__main__":
    unittest.main()
