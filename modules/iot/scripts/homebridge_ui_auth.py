"""Reconcile the Homebridge UI administrator with sealed runtime credentials."""
# Direct, fixed error messages are appropriate for this standalone startup check.
# ruff: file-ignore[too-many-statements]

import hashlib
import hmac
import json
import os
import secrets
import stat
import sys
import tempfile
from pathlib import Path

ITERATIONS = 210_000  # Homebridge Config UI X 5.29.0
MAX_USERNAME_LENGTH = 128
MIN_PASSWORD_LENGTH = 16
EXPECTED_ARGUMENT_COUNT = 4


def read_credential(path: Path) -> str:
    """Read one sealed, single-line credential without changing its contents.

    Returns:
        The credential value.

    Raises:
        ValueError: The value is empty or contains a line break.

    """
    value = path.read_text(encoding="utf-8").removesuffix("\n")
    if not value or "\n" in value or "\r" in value:
        raise ValueError("invalid Homebridge UI credential")
    return value


def password_hash(password: str, salt: str, iterations: int = ITERATIONS) -> str:
    """Match Homebridge Config UI X's PBKDF2 password verifier.

    Returns:
        The hexadecimal password hash.

    """
    return hashlib.pbkdf2_hmac(
        "sha512", password.encode("utf-8"), salt.encode("utf-8"), iterations, 64
    ).hex()


def reconcile(username: str, password: str, auth_path: Path) -> bool:
    """Update the sole UI account and preserve its two-factor enrollment.

    Returns:
        Whether the account file changed.

    Raises:
        ValueError: The credential or existing account file is unsuitable.

    """
    if len(username) > MAX_USERNAME_LENGTH or len(password) < MIN_PASSWORD_LENGTH:
        raise ValueError("invalid Homebridge UI credential length")

    if auth_path.is_symlink():
        raise ValueError("Homebridge UI auth file must not be a symlink")
    if auth_path.exists():
        mode = auth_path.stat().st_mode
        if not stat.S_ISREG(mode):
            raise ValueError("Homebridge UI auth path must be a regular file")
        users = json.loads(auth_path.read_text(encoding="utf-8"))
        if not isinstance(users, list) or not all(
            isinstance(user, dict) for user in users
        ):
            raise ValueError("invalid Homebridge UI auth document")
        admins = [user for user in users if user.get("admin") is True]
        if len(admins) != 1 or len(users) != 1:
            raise ValueError("Homebridge UI must have exactly one managed account")
        admin = admins[0]
        try:
            iterations = int(admin.get("passwordIterations", 1000))
            existing_hash = password_hash(password, admin["salt"], iterations)
            unchanged = admin.get("username") == username and hmac.compare_digest(
                existing_hash, admin["hashedPassword"]
            )
        except KeyError, TypeError, ValueError:
            unchanged = False
        if unchanged:
            return False
        admin["username"] = username
        admin["sessionVersion"] = int(admin.get("sessionVersion", 0)) + 1
    else:
        auth_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        admin = {
            "id": 1,
            "username": username,
            "name": "Administrator",
            "admin": True,
            "sessionVersion": 0,
        }
        users = [admin]

    salt = secrets.token_hex(32)
    admin["salt"] = salt
    admin["hashedPassword"] = password_hash(password, salt)
    admin["passwordIterations"] = ITERATIONS

    fd, temporary = tempfile.mkstemp(prefix=".auth.json.", dir=auth_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(users, output, indent=4)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        Path(temporary).chmod(0o600)
        Path(temporary).replace(auth_path)
        directory_fd = os.open(auth_path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if Path(temporary).exists():
            Path(temporary).unlink()
    return True


if __name__ == "__main__":
    if len(sys.argv) != EXPECTED_ARGUMENT_COUNT:
        raise SystemExit(
            "usage: homebridge-ui-auth USERNAME_FILE PASSWORD_FILE AUTH_FILE"
        )
    reconcile(
        read_credential(Path(sys.argv[1])),
        read_credential(Path(sys.argv[2])),
        Path(sys.argv[3]),
    )
