"""Serve the fixed Codex fixture protocol without accessing external accounts."""

import json
import os
import pathlib
import sys

home = pathlib.Path(os.environ["CODEX_HOME"])
assert "OPENAI_API_KEY" not in os.environ
if "debug" in sys.argv:
    print(json.dumps({"models": [{"slug": "fixture-model"}]}), flush=True)
    sys.exit(0)
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialized":
        continue
    result = {}
    if method == "account/read" and (home / "malformed").exists():
        print("INVALID FRAME", flush=True)
        continue
    if method == "account/read":
        if (home / "approve").exists():
            (home / "auth.json").write_text("public-fixture")
            print(
                json.dumps({
                    "method": "account/login/completed",
                    "params": {"loginId": "fixture-login", "success": True},
                }),
                flush=True,
            )
        result = {
            "account": {"type": "chatgpt", "email": "PRIVATE ACCOUNT FIELD"}
            if (home / "auth.json").exists()
            else None
        }
    if method == "account/login/start":
        if (home / "fail").exists():
            print(
                json.dumps({
                    "id": message["id"],
                    "error": {"message": "PRIVATE AUTH ERROR"},
                }),
                flush=True,
            )
            continue
        result = {
            "type": "chatgptDeviceCode",
            "loginId": "fixture-login",
            "verificationUrl": "https://auth.openai.com/codex/device",
            "userCode": "TEST-CODE",
            "accessToken": "PRIVATE TOKEN",
        }
        if message["params"]["type"] == "chatgpt":
            assert message["params"]["useHostedLoginSuccessPage"] is True
            result = {
                "type": "chatgpt",
                "loginId": "fixture-login",
                "authUrl": "https://auth.openai.com/oauth/authorize?redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&state=public-fixture&code_challenge=public-fixture",
                "accessToken": "PRIVATE TOKEN",
            }
        if (home / "bad-url").exists():
            result["verificationUrl"] = "https://evil.example/device"
            result["authUrl"] = "https://evil.example/device"
        if (home / "bad-callback").exists():
            result["authUrl"] = (
                "https://auth.openai.com/oauth/authorize?redirect_uri=https%3A%2F%2Fevil.example%2Fauth%2Fcallback"
            )
        if (home / "bad-userinfo").exists():
            result["authUrl"] = (
                "https://evil@auth.openai.com/oauth/authorize?redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback"
            )
        if (home / "bad-port").exists():
            result["authUrl"] = (
                "https://auth.openai.com:bad/oauth/authorize?redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback"
            )
    if method == "account/logout":
        (home / "auth.json").unlink(missing_ok=True)
        (home / "approve").unlink(missing_ok=True)
    print(json.dumps({"id": message["id"], "result": result}), flush=True)
