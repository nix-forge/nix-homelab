"""Install a private NZBGet credential fragment without replacing UI settings."""

import os
import re
import sys
import tempfile
from pathlib import Path

try:
    source = Path(os.environ["CREDENTIALS_DIRECTORY"]) / "nzbget-credentials"
    target = Path(sys.argv[1])
    replacements = {}
    for line in source.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or not re.fullmatch(
            r"(?:ControlUsername|ControlPassword|RestrictedUsername|RestrictedPassword|AddUsername|AddPassword|Server[1-9][0-9]*\.(?:Username|Password))",
            key,
        ):
            raise ValueError("invalid credential name")
        if key in replacements or not value or "\x00" in value:
            raise ValueError("invalid credential value")
        replacements[key] = value
    if not replacements.get("ControlPassword"):
        raise ValueError("missing control password")
    lines = target.read_text(encoding="utf-8").splitlines()
    retained = [line for line in lines if line.partition("=")[0] not in replacements]
    retained.extend(f"{key}={value}" for key, value in replacements.items())
    os.umask(0o077)
    descriptor, name = tempfile.mkstemp(prefix=".credentials-", dir=target.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "w") as handle:
            handle.write("\n".join(retained) + "\n")
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
except OSError, ValueError, KeyError, IndexError:
    sys.exit("Could not install NZBGet runtime credentials")
