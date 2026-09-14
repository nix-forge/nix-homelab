import re
import unittest
from pathlib import Path

import yaml


class CITriggerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        workflow = Path(__file__).parents[2] / ".github" / "workflows" / "ci.yml"
        cls.configuration = yaml.load(workflow.read_text(), Loader=yaml.BaseLoader)
        pages = Path(__file__).parents[2] / ".github" / "workflows" / "pages.yml"
        cls.pages = yaml.load(pages.read_text(), Loader=yaml.BaseLoader)

    def test_full_ci_runs_on_main_push(self):
        branches = self.configuration["on"]["push"]["branches"]
        self.assertIn("main", branches)

    def test_full_ci_has_weekly_drift_check(self):
        schedules = self.configuration["on"]["schedule"]
        self.assertTrue(any(schedule.get("cron") for schedule in schedules))

    def test_x86_runtime_smoke_suite_is_available_on_pull_requests(self):
        steps = self.configuration["jobs"]["flake-check"]["steps"]
        kvm = next(
            step
            for step in steps
            if step.get("name") == "Enable KVM for NixOS runtime tests"
        )
        self.assertIn("x86_64-linux", kvm["if"])
        native_checks = next(
            step for step in steps if step.get("name") == "Run native checks"
        )
        self.assertIn("ciChecks", native_checks["with"]["checks-output"])
        self.assertIn("checks", native_checks["with"]["checks-output"])
        timeout = self.configuration["jobs"]["flake-check"]["timeout-minutes"]
        self.assertIn("120", timeout)
        self.assertIn("30", timeout)

    def test_pages_deployment_is_main_only_least_privilege_and_immutably_pinned(self):
        self.assertEqual(self.pages["on"]["push"]["branches"], ["main"])
        self.assertEqual(self.pages["permissions"], {})
        self.assertEqual(
            self.pages["jobs"]["deploy"]["permissions"],
            {
                "actions": "read",
                "contents": "read",
                "id-token": "write",
                "pages": "write",
            },
        )
        uses = [
            step["uses"]
            for job in self.pages["jobs"].values()
            for step in job["steps"]
            if "uses" in step
        ]
        self.assertTrue(uses)
        self.assertTrue(all(re.search(r"@[0-9a-f]{40}$", item) for item in uses))


if __name__ == "__main__":
    unittest.main()
