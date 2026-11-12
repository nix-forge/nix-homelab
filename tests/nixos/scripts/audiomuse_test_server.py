"""Validate generated artifacts in an isolated build or VM fixture."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import override


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/health/ready":
            self.send_response(200)
        else:
            self.send_response(404)
        self.end_headers()

    @override
    def log_message(self, format: str, *_args: object) -> None:
        pass


ThreadingHTTPServer(("127.0.0.1", 18000), Handler).serve_forever()
