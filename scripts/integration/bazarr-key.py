"""Merge Bazarr's runtime API key into its private YAML before application start."""

import os
import re
import sys
import tempfile
from pathlib import Path

import yaml

try:
    key = (
        (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "homelab-api-key")
        .read_text()
        .strip()
    )
    if not re.fullmatch(r"[A-Za-z0-9]{32}", key):
        sys.exit("Bazarr API key must contain exactly 32 alphanumeric characters")
    target = Path(sys.argv[1]) / "config" / "config.yaml"
    os.umask(0o077)
    target.parent.mkdir(parents=True, exist_ok=True)
    existing = yaml.safe_load(target.read_text()) if target.exists() else {}
    existing = existing or {}
    existing.setdefault("auth", {})["apikey"] = key
    existing.setdefault("general", {}).setdefault("ip", "127.0.0.1")
    descriptor, name = tempfile.mkstemp(prefix=".homelab-key-", dir=target.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(yaml.safe_dump(existing))
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
except OSError, ValueError, TypeError, AttributeError, yaml.YAMLError:
    sys.exit("Could not install runtime Bazarr API key")
