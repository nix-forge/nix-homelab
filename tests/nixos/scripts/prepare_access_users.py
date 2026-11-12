"""Validate generated artifacts in an isolated build or VM fixture."""

import json
import pathlib

from argon2 import PasswordHasher

password = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1).hash(
    "disposable-password"
)
# JSON is valid YAML and avoids interpolating hash metacharacters.
with pathlib.Path("/run/access-fixture/users").open("w", encoding="utf-8") as users:
    json.dump(
        {
            "users": {
                "fixture": {
                    "displayname": "Fixture",
                    "password": password,
                    "email": "fixture@example.invalid",
                    "groups": ["media"],
                }
            }
        },
        users,
    )
