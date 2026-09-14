"""Install a runtime Servarr environment file from a systemd credential."""

import os
import re
import sys
from pathlib import Path

kind, destination = sys.argv[1:]
if kind not in {"SONARR", "RADARR", "LIDARR", "PROWLARR"}:
    sys.exit("Unsupported application")
try:
    key = (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "api-key").read_text().strip()
    if not re.fullmatch(r"[A-Za-z0-9]{32}", key):
        sys.exit("Servarr API key must contain exactly 32 alphanumeric characters")
    os.umask(0o077)
    target = Path(destination)
    temporary = target.with_suffix(".tmp")
    temporary.write_text(f"{kind}__AUTH__APIKEY={key}\n")
    temporary.replace(target)
except OSError:
    sys.exit("Could not install runtime API key")
