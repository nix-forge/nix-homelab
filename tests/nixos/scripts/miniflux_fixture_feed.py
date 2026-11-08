"""Validate generated artifacts in an isolated build or VM fixture."""

import base64
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import override

BODY = b"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Fixture reporting</title>
<link>http://127.0.0.1:18999/</link><description>Test feed</description>
<item><title>Verified fixture report</title>
<link>http://127.0.0.1:18999/story</link>
<guid>fixture-report-1</guid><description>Original reporting.</description>
</item></channel></rss>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/photo.webp":
            image = base64.b64decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/xsAAAAASUVORK5CYII="
            )
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.end_headers()
            self.wfile.write(image)
            return
        if self.path == "/story":
            article = (
                '<article><h1>Verified report</h1><figure><img src="http://127.0.0.1:18999/photo.webp"><figcaption>Publisher credit</figcaption></figure><p>'
                + "Evidence from original reporting. " * 80
                + "</p></article>"
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(article)
            return
        if self.path != "/feed.xml":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/rss+xml")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    @override
    def log_message(self, format: str, *_args: object) -> None:
        pass


HTTPServer(("127.0.0.1", 18999), Handler).serve_forever()
