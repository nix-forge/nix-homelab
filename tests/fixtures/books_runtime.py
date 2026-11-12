"""Public Komga 1.26.3 API fixture; all accounts and images are disposable."""

import base64
import io
import json
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image

BASE = "http://127.0.0.1:25600"
PASSWORD = "disposable-reader-password"
ROOT = Path("/srv/media/library/books")


def api(method, path, body=None, user="admin", expected=200, headers=None):
    headers = dict(headers or {})
    if user:
        token = base64.b64encode(f"{user}@example.test:{PASSWORD}".encode()).decode()
        headers["Authorization"] = f"Basic {token}"
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers=headers,
        method=method,
    )
    try:
        response = urllib.request.urlopen(request, timeout=15)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        data = response.read()
        assert response.status == expected, (method, path, response.status, data[:500])
        if "application/json" in response.headers.get("Content-Type", ""):
            return json.loads(data) if data else None
        return data


def page():
    output = io.BytesIO()
    Image.new("RGB", (320, 480), (20, 120, 180)).save(output, format="PNG")
    return output.getvalue()


def verify(book_id):
    assert api("GET", f"/api/v1/books/{book_id}/pages/1", user="reader") == page()
    api("GET", f"/api/v1/books/{book_id}/pages/1", user=None, expected=401)
    api("GET", "/api/v2/users", user="reader", expected=403)
    api("GET", f"/api/v1/books/{book_id}/file", user="reader", expected=403)
    book = api("GET", f"/api/v1/books/{book_id}", user="reader")
    assert book["readProgress"]["completed"] is True, book
    with zipfile.ZipFile(ROOT / "Public series" / "Public book.cbz") as archive:
        assert archive.read("page001.png") == page()


if sys.argv[1] == "seed":
    directory = ROOT / "Public series"
    directory.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(directory / "Public book.cbz", "w") as archive:
        archive.writestr("page001.png", page())
elif sys.argv[1] == "setup":
    api(
        "POST",
        "/api/v1/claim",
        user=None,
        headers={
            "X-Komga-Email": "admin@example.test",
            "X-Komga-Password": PASSWORD,
        },
    )
    library = api(
        "POST", "/api/v1/libraries", {"name": "Public fixture", "root": str(ROOT)}
    )
    api(
        "POST",
        "/api/v2/users",
        {
            "email": "reader@example.test",
            "password": PASSWORD,
            "roles": ["PAGE_STREAMING"],
            "sharedLibraries": {"all": False, "libraryIds": [library["id"]]},
        },
        expected=201,
    )
    api("POST", f"/api/v1/libraries/{library['id']}/scan", expected=202)
    deadline = time.monotonic() + 120
    while True:
        books = api("POST", "/api/v1/books/list", {})["content"]
        if books and books[0]["media"]["status"] == "READY":
            break
        assert time.monotonic() < deadline, books
        time.sleep(1)
    book_id = books[0]["id"]
    api(
        "PATCH",
        f"/api/v1/books/{book_id}/read-progress",
        {"completed": True},
        user="reader",
        expected=204,
    )
    Path("/run/fixture-book-id").write_text(book_id, encoding="utf-8")
    verify(book_id)
else:
    verify(Path("/run/fixture-book-id").read_text(encoding="utf-8"))
