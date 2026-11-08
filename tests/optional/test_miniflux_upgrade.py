"""Content upgrades preserve account choices and repair only useful excerpts."""

import base64
import copy
import importlib.util
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / "scripts/optional/bootstrap_miniflux.py"
spec = importlib.util.spec_from_file_location("miniflux_bootstrap", SOURCE)
assert spec is not None
assert spec.loader is not None
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


class UpgradeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.state = Path(self.directory.name) / "upgrade.json"
        self.feeds: list[dict[str, Any]] = [
            {
                "id": 1,
                "feed_url": "https://example.test/rss",
                "disabled": False,
                "crawler": False,
                "rewrite_rules": "custom",
                "scraper_rules": ".custom",
            },
            {"id": 2, "feed_url": "https://example.test/old", "disabled": False},
            {"id": 3, "feed_url": "https://example.test/disabled", "disabled": True},
        ]
        self.entries: dict[int, dict[str, Any]] = {
            i: {
                "id": i,
                "content": "<p>A short summary.</p>",
                "status": "unread",
                "starred": True,
            }
            for i in range(1, 5)
        }
        self.entries[4]["status"] = "read"
        self.user: dict[str, Any] = {"id": 1, "stylesheet": "p {color: blue}"}
        self.calls = []
        self.failures_remaining = 3
        self.policy: dict[str, Any] = {
            "publicUrl": "https://reader.example.test",
            "feeds": [
                {
                    "url": "https://example.test/rss",
                    "crawler": True,
                    "rewriteRules": "add_dynamic_image",
                },
                {"url": "https://example.test/deleted", "crawler": True},
                {"url": "https://example.test/disabled", "crawler": True},
            ],
            "disabledFeeds": ["https://example.test/old"],
            "backfillLimit": 4,
            "stylesheet": "body {line-height: 1.7}",
        }

    def api(self, _base, _auth, method, path, payload=None):  # ruff: ignore[too-many-return-statements]
        self.calls.append((method, path, payload))
        if method == "PUT":
            assert payload is not None
            if path.startswith("/v1/entries/"):
                self.entries[int(path.split("/")[3])].update(payload)
            elif path.startswith("/v1/users/"):
                self.user.update(payload)
            else:
                self.feeds[int(path.split("/")[3]) - 1].update(payload)
            return {}
        if path == "/v1/feeds":
            return copy.deepcopy(self.feeds)
        if path == "/v1/me":
            return copy.deepcopy(self.user)
        if "/feeds/1/entries?" in path:
            return {"entries": copy.deepcopy(list(self.entries.values()))}
        if "/fetch-content" in path:
            index = int(path.split("/")[3])
            if index == 2:
                return {"content": "<p>Unavailable.</p>"}
            if index == 3 and self.failures_remaining:
                self.failures_remaining -= 1
                raise RuntimeError("HTTP 503")
            return {
                "content": '<figure><img src="https://example.test/photo.webp"><figcaption>Credit</figcaption></figure><p>'
                + "Reporting evidence. " * 150
                + "</p>"
            }
        if path.startswith("/v1/entries/"):
            return copy.deepcopy(self.entries[int(path.split("/")[3])])
        raise AssertionError(f"Unexpected API call {method} {path}")

    def run_once(self):
        with patch.object(reader, "api", self.api):
            return reader.upgrade_reader(
                "http://127.0.0.1:18080", "fixture", "fixture", self.policy, self.state
            )

    def upgrade(self):
        for _ in range(3):
            try:
                return self.run_once()
            except RuntimeError as error:
                self.assertIn("pending retries", str(error))
        raise AssertionError("Upgrade did not finish within its retry bound")

    def test_initial_import_resumes_failed_configuration_without_duplicate_creation(
        self,
    ):
        records = []
        put_attempts = []
        desired = {
            "url": "https://example.test/new",
            "category": "Science",
            "crawler": True,
            "scraperRules": "article",
        }

        def initial_api(_base, _auth, method, path, payload=None):
            if path == "/v1/me":
                return {"id": 1}
            if path == "/v1/categories":
                return [{"id": 1, "title": "Science"}]
            if path == "/v1/feeds" and method == "GET":
                return records.copy()
            if path == "/v1/feeds" and method == "POST":
                assert payload is not None
                self.assertFalse(payload["crawler"])
                records.append({"feed_url": desired["url"], "id": 9})
                return {"feed_id": 9}
            if path == "/v1/feeds/9":
                put_attempts.append(payload)
                if len(put_attempts) == 1:
                    raise RuntimeError("Interrupted after feed creation")
            return None

        with patch.object(reader, "api", initial_api):
            with self.assertRaises(RuntimeError):
                reader.import_feeds(
                    "http://127.0.0.1:18080",
                    "fixture",
                    "fixture",
                    [desired],
                    self.state,
                )
            reader.import_feeds(
                "http://127.0.0.1:18080", "fixture", "fixture", [desired], self.state
            )
        self.assertEqual(len(records), 1)
        self.assertEqual(len(put_attempts), 2)
        self.assertTrue(put_attempts[-1]["crawler"])
        self.assertEqual(put_attempts[-1]["scraper_rules"], "article")
        self.assertFalse(self.state.exists())

    def test_transient_error_retries_without_reapplying_configuration(self):
        with self.assertRaisesRegex(RuntimeError, "pending retries"):
            self.run_once()
        self.failures_remaining = 0
        self.calls.clear()
        result = self.run_once()
        self.assertTrue(result["complete"])
        self.assertEqual(result["failed"], 0)
        self.assertEqual(result["updated"], 2)
        self.assertFalse(any(path == "/v1/feeds" for _, path, _ in self.calls))

    def test_display_proxy_urls_are_restored_before_storage(self):
        url = "https://publisher.example.test/photo.webp?width=1600&signature=unchanged"
        encoded = base64.urlsafe_b64encode(url.encode()).decode()
        proxy = f"https://reader.example.test/proxy/signed/{encoded}"
        content = f'<img src="{proxy}" srcset="{proxy} 1600w">'
        restored = reader.restore_publisher_urls(content, self.policy["publicUrl"])
        self.assertNotIn("/proxy/", restored)
        self.assertEqual(restored.count("width=1600&amp;signature=unchanged"), 2)
        self.assertEqual(
            reader.restore_publisher_urls(content, "https://other.example.test"),
            content,
        )
        self.assertEqual(
            reader.restore_publisher_urls(
                '<img src="https://reader.example.test/proxy/signed/invalid">',
                self.policy["publicUrl"],
            ),
            '<img src="https://reader.example.test/proxy/signed/invalid">',
        )

    def test_repairs_content_without_read_star_or_custom_rule_changes(self):
        result = self.upgrade()
        self.assertEqual(
            (result["updated"], result["skipped"], result["failed"]), (1, 2, 1)
        )
        self.assertIn("<figcaption>Credit</figcaption>", self.entries[1]["content"])
        self.assertEqual(self.entries[1]["status"], "unread")
        self.assertTrue(self.entries[1]["starred"])
        self.assertEqual(self.entries[2]["content"], "<p>A short summary.</p>")
        self.assertEqual(self.entries[3]["content"], "<p>A short summary.</p>")
        self.assertEqual(self.feeds[0]["rewrite_rules"], "custom")
        self.assertEqual(self.feeds[0]["scraper_rules"], ".custom")
        self.assertTrue(self.feeds[0]["crawler"])
        self.assertTrue(self.feeds[1]["disabled"])
        self.assertEqual(self.user["stylesheet"], "p {color: blue}")
        self.assertFalse(
            any(method in {"POST", "DELETE"} for method, _, _ in self.calls)
        )
        self.assertFalse(any(path == "/v1/feeds/3" for _, path, _ in self.calls))

    def test_completed_revision_never_reconciles_user_changes(self):
        self.upgrade()
        self.calls.clear()
        self.feeds[0]["crawler"] = False
        self.upgrade()
        self.assertEqual(self.calls, [])
        self.assertFalse(self.feeds[0]["crawler"])

    def test_style_and_rules_apply_only_to_empty_fields(self):
        self.user["stylesheet"] = ""
        self.feeds[0].update(rewrite_rules="", scraper_rules="")
        self.policy["feeds"][0]["scraperRules"] = "article"
        self.upgrade()
        self.assertEqual(self.user["stylesheet"], self.policy["stylesheet"])
        self.assertEqual(self.feeds[0]["rewrite_rules"], "add_dynamic_image")
        self.assertEqual(self.feeds[0]["scraper_rules"], "article")

    def test_zero_backfill_does_not_fetch_articles(self):
        self.policy["backfillLimit"] = 0
        self.upgrade()
        self.assertFalse(any("/entries" in path for _, path, _ in self.calls))

    def test_rejects_non_loopback_api_before_credentials_leave_process(self):
        with self.assertRaises(ValueError):
            reader.api("https://example.test", "private-fixture", "GET", "/v1/me")


if __name__ == "__main__":
    unittest.main()
