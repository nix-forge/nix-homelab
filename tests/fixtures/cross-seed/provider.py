"""Public local torrents with equal file trees and different piece sizes."""

import hashlib
import json
import sys
import time
import urllib.parse
from email.utils import formatdate
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

NAME = "Workflow.Fixture.2026.1080p.WEB-DL.mkv"
DATA = (Path(sys.argv[1]) / NAME).read_bytes()
STATE = {"enabled": False, "searches": 0, "webseedBytes": 0, "candidateGrabs": 0}


def encode(value):
    if isinstance(value, int):
        return b"i" + str(value).encode() + b"e"
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, bytes):
        return str(len(value)).encode() + b":" + value
    if isinstance(value, list):
        return b"l" + b"".join(map(encode, value)) + b"e"
    return b"d" + b"".join(encode(key) + encode(value[key]) for key in sorted(value)) + b"e"


def torrent(piece_size):
    info = {
        "name": NAME,
        "length": len(DATA),
        "piece length": piece_size,
        "pieces": b"".join(
            hashlib.sha1(DATA[offset : offset + piece_size]).digest()
            for offset in range(0, len(DATA), piece_size)
        ),
    }
    return (
        encode({"info": info, "url-list": ["http://127.0.0.1:18091/" + NAME]}),
        hashlib.sha1(encode(info)).hexdigest(),
    )


ORIGINAL, ORIGINAL_HASH = torrent(16384)
CANDIDATE, CANDIDATE_HASH = torrent(32768)
assert ORIGINAL_HASH != CANDIDATE_HASH


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def send(self, data, content_type="application/json", status=200, headers=None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path == "/enable":
            STATE["enabled"] = True
            self.send(b"{}")
        else:
            self.send(b"{}", status=404)

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        if parsed.path == "/stats":
            self.send(
                json.dumps(
                    {**STATE, "original": ORIGINAL_HASH, "candidate": CANDIDATE_HASH}
                ).encode()
            )
        elif parsed.path == "/original.torrent":
            self.send(ORIGINAL, "application/x-bittorrent")
        elif parsed.path == "/candidate.torrent":
            STATE["candidateGrabs"] += 1
            self.send(CANDIDATE, "application/x-bittorrent")
        elif parsed.path == "/" + NAME:
            start, end = 0, len(DATA) - 1
            if self.headers.get("Range"):
                values = self.headers["Range"].removeprefix("bytes=").split("-")
                start, end = int(values[0]), int(values[1]) if values[1] else end
            data = DATA[start : end + 1]
            STATE["webseedBytes"] += len(data)
            self.send(
                data,
                "video/x-matroska",
                206 if self.headers.get("Range") else 200,
                {"Content-Range": f"bytes {start}-{end}/{len(DATA)}"},
            )
        elif parsed.path == "/api" and query.get("t") == ["caps"]:
            self.send(
                b'<caps><limits max="100" default="100"/><searching><search available="yes" supportedParams="q"/><movie-search available="yes" supportedParams="q"/></searching><categories><category id="2000" name="Movies"/></categories></caps>',
                "application/xml",
            )
        elif parsed.path == "/api":
            STATE["searches"] += 1
            item = ""
            if STATE["enabled"]:
                item = f'''<item><title>Workflow.Fixture.2026.1080p.WEB-DL</title><guid>public-cross-seed-candidate</guid><link>http://127.0.0.1:18091/candidate.torrent</link><pubDate>{formatdate(time.time(), usegmt=True)}</pubDate><size>{len(DATA)}</size><category>2000</category><enclosure url="http://127.0.0.1:18091/candidate.torrent" length="{len(DATA)}" type="application/x-bittorrent"/><torznab:attr name="seeders" value="1"/><torznab:attr name="peers" value="1"/></item>'''
            self.send(
                (
                    '<?xml version="1.0"?><rss version="2.0" xmlns:torznab="http://torznab.com/schemas/2015/feed"><channel><title>Public cross-seed fixture</title>'
                    + item
                    + "</channel></rss>"
                ).encode(),
                "application/xml",
            )
        else:
            self.send(b"{}", status=404)


ThreadingHTTPServer(("127.0.0.1", 18091), Handler).serve_forever()
