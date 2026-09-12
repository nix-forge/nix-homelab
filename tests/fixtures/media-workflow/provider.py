"""Disposable external metadata and HTTP torrent webseed, never application mocks."""

import hashlib
import json
import ssl
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

DIRECTORY = Path(sys.argv[1])
NAME = "Workflow.Fixture.2026.1080p.WEB-DL.mkv"
MOVIE = {
    "tmdbId": 999999,
    "imdbId": "tt9999999",
    "title": "Workflow Fixture",
    "originalTitle": "Workflow Fixture",
    "titleSlug": "workflow-fixture-999999",
    "overview": "A generated blue test image, not commercial media.",
    "runtime": 2,
    "year": 2026,
    "status": "released",
    "originalLanguage": "en",
    "inCinema": "2026-01-01T00:00:00Z",
    "physicalRelease": "2026-01-01T00:00:00Z",
    "images": [],
    "genres": [],
    "keywords": [],
    "ratings": [{"count": 1, "value": 5.0}],
    "alternativeTitles": [],
    "translations": [],
    "certifications": [],
    "credits": {"cast": [], "crew": []},
    "recommendations": [],
}


def bencode(value):
    if isinstance(value, int):
        return b"i" + str(value).encode() + b"e"
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, bytes):
        return str(len(value)).encode() + b":" + value
    if isinstance(value, list):
        return b"l" + b"".join(bencode(item) for item in value) + b"e"
    return b"d" + b"".join(bencode(key) + bencode(value[key]) for key in sorted(value)) + b"e"


DATA = (DIRECTORY / NAME).read_bytes()
COUNTS = {"search": 0, "torrent": 0, "webseed": 0}
TORRENT = bencode(
    {
        "info": {
            "name": NAME,
            "length": len(DATA),
            "piece length": 16384,
            "pieces": b"".join(
                hashlib.sha1(DATA[i : i + 16384]).digest() for i in range(0, len(DATA), 16384)
            ),
        },
        "url-list": ["http://127.0.0.1:18090/" + NAME],
    }
)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/" + NAME:
            COUNTS["webseed"] += 1
            body, kind = DATA, "video/x-matroska"
        elif path == "/fixture.torrent":
            COUNTS["torrent"] += 1
            body, kind = TORRENT, "application/x-bittorrent"
        elif path == "/stats":
            body, kind = json.dumps(COUNTS).encode(), "application/json"
        elif path == "/api":
            query = parse_qs(urlsplit(self.path).query)
            if query.get("t") == ["caps"]:
                xml = '<caps><server title="Public fixture"/><limits max="100" default="100"/><searching><search available="yes" supportedParams="q"/><movie-search available="yes" supportedParams="q,tmdbid"/></searching><categories><category id="2000" name="Movies"/></categories></caps>'
            else:
                COUNTS["search"] += 1
                xml = (
                    '<rss version="2.0" xmlns:torznab="http://torznab.com/schemas/2015/feed"><channel><title>Public fixture</title><item>'
                    "<title>Workflow.Fixture.2026.1080p.WEB-DL</title><guid>public-workflow-fixture</guid>"
                    "<link>http://127.0.0.1:18090/fixture.torrent</link><pubDate>Sat, 12 Sep 2026 00:00:00 GMT</pubDate>"
                    "<category>2000</category>"
                    f'<enclosure url="http://127.0.0.1:18090/fixture.torrent" length="{len(DATA)}" type="application/x-bittorrent"/>'
                    '<torznab:attr name="seeders" value="1"/><torznab:attr name="peers" value="1"/>'
                    '<torznab:attr name="tmdbid" value="999999"/></item></channel></rss>'
                )
            body, kind = xml.encode(), "application/xml"
        elif path == "/3/movie/999999":
            movie = {
                "id": 999999,
                "title": "Workflow Fixture",
                "original_title": "Workflow Fixture",
                "original_language": "en",
                "release_date": "2026-01-01",
                "runtime": 2,
                "overview": MOVIE["overview"],
                "status": "Released",
                "adult": False,
                "video": False,
                "genres": [],
                "poster_path": None,
                "backdrop_path": None,
                "production_companies": [],
                "production_countries": [],
                "spoken_languages": [],
                "budget": 0,
                "revenue": 0,
                "popularity": 1,
                "tagline": "",
                "homepage": "",
                "imdb_id": "tt9999999",
                "external_ids": {"imdb_id": "tt9999999"},
                "credits": {"cast": [], "crew": []},
                "keywords": {"keywords": []},
                "videos": {"results": []},
                "release_dates": {"results": []},
                "watch/providers": {"results": {}},
                "belongs_to_collection": None,
                "vote_average": 5,
                "vote_count": 1,
            }
            body, kind = json.dumps(movie).encode(), "application/json"
        elif path.endswith("/movie/999999"):
            body, kind = json.dumps(MOVIE).encode(), "application/json"
        else:
            self.send_error(404)
            return
        status = 200
        if "Range" in self.headers:
            start, end = self.headers["Range"].removeprefix("bytes=").split("-")
            start, end = int(start), int(end) if end else len(body) - 1
            total = len(body)
            body = body[start : end + 1]
            status = 206
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    do_HEAD = do_GET


http = ThreadingHTTPServer(("127.0.0.1", 18090), Handler)
threading.Thread(target=http.serve_forever, daemon=True).start()
https = ThreadingHTTPServer(("127.0.0.1", 443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(DIRECTORY / "cert.pem", DIRECTORY / "key.pem")
https.socket = context.wrap_socket(https.socket, server_side=True)
https.serve_forever()
