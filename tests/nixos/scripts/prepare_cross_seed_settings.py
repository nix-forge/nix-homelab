"""Validate generated artifacts in an isolated build or VM fixture."""

import base64
import hashlib
import json
import pathlib

salt = b"public-cross-seed-salt"
password = b"public-cross-seed-password"
digest = hashlib.pbkdf2_hmac("sha512", password, salt, 100000)
encoded = base64.b64encode(salt).decode() + ":" + base64.b64encode(digest).decode()
pathlib.Path("/run/cross-seed-qbit.ini").write_text(
    '[Preferences]\nWebUI\\Username=admin\nWebUI\\Password_PBKDF2="@ByteArray('
    + encoded
    + ')"\n',
    encoding="utf-8",
)
with pathlib.Path("/run/cross-seed-settings.json").open(
    "w", encoding="utf-8"
) as handle:
    json.dump(
        {
            "apiKey": "public-cross-seed-api-key-0123456789",
            "torrentClients": [
                "qbittorrent:http://admin:public-cross-seed-password@127.0.0.1:8081"
            ],
            "torznab": ["http://127.0.0.1:18091/api?apikey=public-fixture"],
        },
        handle,
    )
