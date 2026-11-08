"""Exercise bootstrap recovery without a live identity provider."""

import importlib.util
import os
import tempfile
import urllib.error
from email.message import Message
from pathlib import Path
from unittest import TestCase, main, mock

spec = importlib.util.spec_from_file_location(
    "keycloak_admin",
    Path(__file__).resolve().parents[2] / "modules/services/scripts/keycloak_admin.py",
)
assert spec is not None
assert spec.loader is not None
admin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(admin)


class Provisioning(TestCase):
    def setUp(self):
        self.created = False
        self.role = False
        self.bootstrap = True
        self.events = []

    def login(self, base, username, password):
        if username == "permanent" and self.created:
            return "permanent-token"
        if username == "temporary" and self.bootstrap:
            return "bootstrap-token"
        raise urllib.error.HTTPError(base, 401, "fixture rejection", Message(), None)

    def request(self, base, path, *, data=None, token=None, method=None, **kwargs):
        self.events.append((path, token, method))
        if token == "permanent-token" and not self.role:
            raise urllib.error.HTTPError(
                base, 403, "fixture lacks role", Message(), None
            )
        if path == "/admin/realms/master":
            return {}
        if "users?username=permanent" in path:
            return [{"id": "permanent-id"}] if self.created else []
        if path == "/admin/realms/master/users":
            self.created = True
            return None
        if path.endswith("/roles/admin"):
            return {"id": "admin-role-id", "name": "admin"}
        if path.endswith("/role-mappings/realm"):
            self.role = True
            return None
        if "users?username=temporary" in path:
            return [{"id": "bootstrap-id"}] if self.bootstrap else []
        if method == "DELETE":
            self.assertTrue(self.role)
            self.assertEqual(token, "permanent-token")
            self.bootstrap = False
            return None
        self.fail("unexpected request")
        return None

    def provision(self):
        with (
            mock.patch.object(admin, "login", side_effect=self.login),
            mock.patch.object(admin, "request", side_effect=self.request),
        ):
            admin.ensure_admin(
                "http://127.0.0.1:1411", "permanent", "fixture", "temporary", "fixture"
            )

    def test_first_start_and_restart(self):
        self.provision()
        self.assertTrue(self.created)
        self.assertTrue(self.role)
        self.assertFalse(self.bootstrap)
        self.provision()
        self.assertEqual(
            sum(path == "/admin/realms/master/users" for path, _, _ in self.events), 1
        )

    def test_recovers_after_user_creation_before_role_assignment(self):
        self.created = True
        self.provision()
        self.assertTrue(self.role)
        self.assertFalse(self.bootstrap)
        self.assertIn(
            ("/admin/realms/master/roles/admin", "bootstrap-token", None), self.events
        )

    def test_colliding_names_do_not_modify_accounts(self):
        with (
            mock.patch.object(admin, "request") as request,
            self.assertRaises(ValueError),
        ):
            admin.ensure_admin("http://127.0.0.1", "same", "fixture", "same", "fixture")
        request.assert_not_called()

    def test_completion_marker_preserves_later_account_changes(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.dict(
                os.environ,
                {
                    "STATE_DIRECTORY": directory,
                    "HOMELAB_KEYCLOAK_URL": "http://127.0.0.1:1411",
                    "HOMELAB_ADMIN_USERNAME": "permanent",
                    "HOMELAB_ADMIN_PASSWORD": "fixture",
                    "KC_BOOTSTRAP_ADMIN_USERNAME": "temporary",
                    "KC_BOOTSTRAP_ADMIN_PASSWORD": "fixture",
                },
            ),
            mock.patch.object(admin, "ensure_admin") as provision,
        ):
            self.assertEqual(admin.main(), 0)
            marker = Path(directory) / "administrator-provisioned"
            self.assertTrue(marker.is_file())
            self.assertEqual(marker.stat().st_mode & 0o777, 0o600)
            self.assertEqual(admin.main(), 0)
            provision.assert_called_once()

    def test_redirects_are_rejected(self):
        with self.assertRaises(ValueError):
            admin.NoRedirect().redirect_request(
                None, None, 307, "redirect", {}, "https://other.example"
            )


if __name__ == "__main__":
    main()
