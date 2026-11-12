"""Verify private startup preparation before recording the listener arguments."""

import json
import sys
from pathlib import Path

preferences, expected_key, marker, *arguments = sys.argv[1:]
if (
    "WebUI\\APIKey=" + expected_key
    not in Path(preferences).read_text(encoding="utf-8").splitlines()
):
    raise SystemExit("Listener started without its configured API key")
Path(marker).write_text(json.dumps(arguments), encoding="utf-8")
