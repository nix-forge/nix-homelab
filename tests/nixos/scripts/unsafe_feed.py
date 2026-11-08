"""Validate generated artifacts in an isolated build or VM fixture."""

import base64
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import override


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"""<rss version="2.0"><channel><title>Safety fixture</title>
        <link>http://127.0.0.1:19000/</link><description>Fixture</description>
        <item><title>Image with unsafe attributes</title><guid>unsafe-1</guid>
        <link>https://example.test/story</link><description><![CDATA[
        <img src="https://example.test/photo.jpg" onerror="alert(1)">
        <script>alert(1)</script><a href="javascript:alert(1)">unsafe</a>
        ]]></description></item></channel></rss>"""
        content_type = "application/rss+xml"
        if self.path == "/":
            body = b'<html><head><link rel="icon" href="/favicon.ico"></head></html>'
            content_type = "text/html"
        elif self.path == "/favicon.ico":
            body = base64.b64decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+lm9sAAAAASUVORK5CYII="
            )
            content_type = "image/png"
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.end_headers()
        self.wfile.write(body)

    @override
    def log_message(self, format: str, *_args: object) -> None:
        pass


HTTPServer(("127.0.0.1", 19000), Handler).serve_forever()
