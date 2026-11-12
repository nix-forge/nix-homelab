"""Serve the fixed Codex fixture protocol without accessing external accounts."""

import json
import os
import pathlib
import sys
import time

if "debug" in sys.argv:
    assert "--bundled" not in sys.argv, "Runtime must refresh the signed-in catalog"
    print(
        json.dumps({
            "models": [
                {
                    "slug": "fixture-model",
                    "shell_type": "unified_exec",
                    "apply_patch_tool_type": "freeform",
                    "experimental_supported_tools": ["clock"],
                }
            ]
        })
    )
    sys.exit(0)
args = sys.argv[1:]
settings = dict(arg.split("=", 1) for arg in args if "=" in arg)
with pathlib.Path(json.loads(settings["model_catalog_json"])).open(
    encoding="utf-8"
) as stream:
    catalog = json.load(stream)
assert catalog["models"][0]["apply_patch_tool_type"] is None
assert catalog["models"][0]["shell_type"] == "disabled"
assert catalog["models"][0]["experimental_supported_tools"] == []
assert settings["features.shell_tool"] == "false"
assert settings["features.view_image"] == "false"
assert "--ignore-user-config" in args
assert "--ignore-rules" in args
assert "OPENAI_API_KEY" not in os.environ
assert "CODEX_API_KEY" not in os.environ
prompt = sys.stdin.read()
if "timeout-fixture" in prompt:
    time.sleep(10)
if "failure-fixture" in prompt:
    print("PRIVATE PROVIDER ERROR", file=sys.stderr)
    sys.exit(1)
output = pathlib.Path(args[args.index("--output-last-message") + 1])
output.write_text('{"description":"fixture outfit"}', encoding="utf-8")
