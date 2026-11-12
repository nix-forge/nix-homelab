"""Validate generated artifacts in an isolated build or VM fixture."""

import base64
import hashlib
import pathlib

salt = b"public-disposable-test-salt"
digest = hashlib.pbkdf2_hmac("sha512", b"fixture-password", salt, 100000)
encoded = base64.b64encode(salt).decode() + ":" + base64.b64encode(digest).decode()
pathlib.Path("/run/test-qbit-webui.ini").write_text(
    '[Preferences]\nWebUI\\Username=fixture\nWebUI\\Password_PBKDF2="@ByteArray('
    + encoded
    + ')"\n',
    encoding="utf-8",
)
