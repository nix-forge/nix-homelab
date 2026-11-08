"""Behavior checks for the sealed Homebridge UI login reconciler."""

import importlib.util
import json
import tempfile
from pathlib import Path

import pytest

SOURCE = Path(__file__).parents[2] / "modules/iot/scripts/homebridge_ui_auth.py"
spec = importlib.util.spec_from_file_location("homebridge_ui_auth", SOURCE)
assert spec is not None
assert spec.loader is not None
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)


def test_create_and_idempotent_reconcile() -> None:
    """A first boot writes a verifier; the next boot leaves it alone."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "auth.json"
        assert auth.reconcile("administrator", "test-password-long-enough", path)
        first = path.read_bytes()
        accounts = json.loads(first)
        assert len(accounts) == 1
        assert accounts[0]["username"] == "administrator"
        assert accounts[0]["hashedPassword"] != "test-password-long-enough"
        assert accounts[0]["passwordIterations"] == auth.ITERATIONS
        assert not auth.reconcile("administrator", "test-password-long-enough", path)
        assert path.read_bytes() == first


def test_rotation_preserves_otp() -> None:
    """Credential rotation keeps the enrolled one-time-password secret."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "auth.json"
        auth.reconcile("old-admin", "test-password-long-enough", path)
        users = json.loads(path.read_text())
        users[0].update(otpActive=True, otpSecret="test-otp-secret")
        path.write_text(json.dumps(users))

        assert auth.reconcile("new-admin", "new-test-password-long-enough", path)
        updated = json.loads(path.read_text())
        assert updated[0]["username"] == "new-admin"
        assert updated[0]["otpSecret"] == "test-otp-secret"
        assert updated[0]["sessionVersion"] == 1
        assert updated[0]["hashedPassword"] == auth.password_hash(
            "new-test-password-long-enough", updated[0]["salt"]
        )


def test_multiple_administrators_fail_without_modifying_auth_file() -> None:
    """An ambiguous administrator choice must not mutate the account file."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "auth.json"
        original = json.dumps([
            {"id": 1, "username": "first", "admin": True},
            {"id": 2, "username": "second", "admin": True},
        ])
        path.write_text(original)
        with pytest.raises(ValueError, match="exactly one managed account"):
            auth.reconcile("administrator", "test-password-long-enough", path)
        assert path.read_text() == original


def test_unmanaged_account_fails_without_modifying_auth_file() -> None:
    """Additional UI passwords cannot silently remain outside Nix seal."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "auth.json"
        auth.reconcile("administrator", "test-password-long-enough", path)
        users = json.loads(path.read_text())
        users.append({"id": 2, "username": "guest", "admin": False})
        original = json.dumps(users)
        path.write_text(original)
        with pytest.raises(ValueError, match="exactly one managed account"):
            auth.reconcile("administrator", "test-password-long-enough", path)
        assert path.read_text() == original
