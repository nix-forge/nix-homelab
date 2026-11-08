"""Validate generated artifacts in an isolated build or VM fixture."""

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import override

state = Path("/var/lib/karakeep")
assert (
    os.environ["MEILI_MASTER_KEY"]
    == state.joinpath("meili-master-key").read_text().strip()
)
assert (
    os.environ["NEXTAUTH_SECRET"]
    == state.joinpath("nextauth-secret").read_text().strip()
)
assert os.environ["MEILI_ADDR"] == "http://127.0.0.1:7700"
assert os.environ["BROWSER_WEB_URL"] == "http://127.0.0.1:19222"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/api/health":
            self.send_error(404)
            return
        body = json.dumps({"status": "ok"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    @override
    def log_message(self, format: str, *_args: object) -> None:
        pass


HTTPServer((os.environ["HOST"], int(os.environ["PORT"])), Handler).serve_forever()
