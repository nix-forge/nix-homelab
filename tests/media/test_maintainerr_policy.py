import json
import pathlib
import sys
import tempfile
import unittest
from typing import Any
from unittest.mock import patch

sys.path.insert(
    0, str(pathlib.Path(__file__).resolve().parents[2] / "scripts" / "media")
)
import maintainerr_policy as policy


def rule(name="Demo") -> dict[str, Any]:
    return {
        "name": name,
        "description": "fixture",
        "libraryId": 1,
        "dataType": "movie",
        "isActive": False,
        "arrAction": 4,
        "useRules": True,
        "rules": [],
        "collection": {
            "deleteAfterDays": 30,
            "overlayEnabled": False,
            "manualCollection": False,
            "manualCollectionName": "",
        },
    }


class PolicyTest(unittest.TestCase):
    def test_rejects_unsafe_actions_and_timers(self):
        for change in (
            lambda item: item.update(arrAction=0),
            lambda item: item["collection"].update(deleteAfterDays=None),
            lambda item: item["collection"].update(deleteAfterDays=36501),
            lambda item: item["collection"].update(overlayEnabled=True),
        ):
            item = rule()
            change(item)
            with self.assertRaises(ValueError):
                policy.validate({"rules": [item]})

    def test_plan_and_apply_preserve_unowned_rules(self):
        upstream = [dict(rule("Manual"), id=7)]
        calls = []

        def api(_base, method, path, payload=None):
            calls.append((method, path))
            if path == "/api/rules":
                if method == "GET":
                    return upstream
                if method == "POST":
                    assert payload is not None
                    upstream.append(dict(payload, id=8))
                    return {"code": 1}
            if path == "/api/overlays/templates" and method == "GET":
                return []
            raise AssertionError((method, path))

        with tempfile.TemporaryDirectory() as directory:
            ledger = pathlib.Path(directory) / "ledger.json"
            with patch.object(policy, "request", side_effect=api):
                policy.reconcile(
                    "http://127.0.0.1:6247", {"rules": [rule()]}, ledger, False
                )
                self.assertFalse(ledger.exists())
                policy.reconcile(
                    "http://127.0.0.1:6247", {"rules": [rule()]}, ledger, True
                )
                self.assertEqual(json.loads(ledger.read_text())["rules"], {"Demo": 8})
                self.assertEqual(upstream[0]["name"], "Manual")
                self.assertFalse(any(method == "DELETE" for method, _ in calls))

    def test_name_collision_fails_before_mutation(self):
        def api(_base, method, path, payload=None):
            self.assertEqual(method, "GET")
            return [dict(rule(), id=3)] if path == "/api/rules" else []

        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(policy, "request", side_effect=api),
            self.assertRaisesRegex(RuntimeError, "collision"),
        ):
            policy.reconcile(
                "http://127.0.0.1:6247",
                {"rules": [rule()]},
                pathlib.Path(directory) / "ledger",
                True,
            )

    def test_existing_rule_preserves_collection_settings_on_update(self):
        old: dict[str, Any] = dict(rule(), id=5, libraryId="1", description="old")
        old["collection"] = {
            **old["collection"],
            "arrAction": 4,
            "visibleOnHome": False,
            "keepLogsForMonths": 12,
        }
        payloads = []

        def api(_base, method, path, payload=None):
            if method == "GET":
                return [old] if path == "/api/rules" else []
            payloads.append(payload)
            return {"code": 1}

        with tempfile.TemporaryDirectory() as directory:
            ledger = pathlib.Path(directory) / "ledger.json"
            ledger.write_text(json.dumps({"rules": {"Demo": 5}, "templates": {}}))
            with patch.object(policy, "request", side_effect=api):
                policy.reconcile(
                    "http://127.0.0.1:6247", {"rules": [rule()]}, ledger, True
                )
        self.assertEqual(payloads[0]["libraryId"], "1")
        self.assertEqual(payloads[0]["collection"]["visibleOnHome"], False)
        self.assertEqual(payloads[0]["collection"]["arrAction"], 4)

    def test_template_creation_records_id_without_deleting_presets(self):
        calls = []

        def api(_base, method, path, payload=None):
            calls.append((method, path))
            if method == "GET":
                return [{"id": 1, "name": "Classic Pill", "isPreset": True}]
            return {"id": 9}

        template = {
            "name": "Review Poster",
            "mode": "poster",
            "canvasWidth": 1000,
            "canvasHeight": 1500,
            "elements": [],
        }
        with tempfile.TemporaryDirectory() as directory:
            ledger = pathlib.Path(directory) / "ledger.json"
            with patch.object(policy, "request", side_effect=api):
                policy.reconcile(
                    "http://127.0.0.1:6247", {"templates": [template]}, ledger, True
                )
            self.assertEqual(
                json.loads(ledger.read_text())["templates"], {"Review Poster": 9}
            )
        self.assertEqual(
            calls,
            [("GET", "/api/overlays/templates"), ("POST", "/api/overlays/templates")],
        )

    def test_owned_template_mode_change_is_rejected(self):
        template = {
            "name": "Review Poster",
            "mode": "titlecard",
            "canvasWidth": 1000,
            "canvasHeight": 1500,
            "elements": [],
        }

        def api(_base, method, path, payload=None):
            self.assertEqual(method, "GET")
            return [
                {"id": 9, "name": "Review Poster", "mode": "poster", "isPreset": False}
            ]

        with tempfile.TemporaryDirectory() as directory:
            ledger = pathlib.Path(directory) / "ledger.json"
            ledger.write_text(
                json.dumps({"rules": {}, "templates": {"Review Poster": 9}})
            )
            with (
                patch.object(policy, "request", side_effect=api),
                self.assertRaisesRegex(RuntimeError, "mode changed"),
            ):
                policy.reconcile(
                    "http://127.0.0.1:6247", {"templates": [template]}, ledger, True
                )


if __name__ == "__main__":
    unittest.main()
