"""Validate generated artifacts in an isolated build or VM fixture."""

from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(self.headers.get("Authorization", "cleared").encode())


HTTPServer(("127.0.0.1", 6247), Handler).serve_forever()
