"""Import a small first-run source list without managing later user choices."""

import base64
import html
import http.client
import json
import os
import re
import sys
from html.parser import HTMLParser
from http import HTTPStatus
from pathlib import Path
from urllib.parse import urlsplit


def api(base_url: str, auth: str, method: str, path: str, payload=None):
    target = urlsplit(base_url)
    if (
        (target.scheme, target.hostname) != ("http", "127.0.0.1")
        or target.port is None
        or any((target.path, target.query, target.fragment, target.username))
    ):
        raise ValueError("Miniflux bootstrap requires a plain loopback API endpoint")
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    connection = http.client.HTTPConnection("127.0.0.1", target.port, timeout=90)
    try:
        connection.request(
            method,
            path,
            body=data,
            headers={
                "Authorization": "Basic " + auth,
                "Content-Type": "application/json",
            },
        )
        response = connection.getresponse()
        content = response.read()
        if response.status not in range(HTTPStatus.OK, HTTPStatus.MULTIPLE_CHOICES):
            raise RuntimeError(
                f"Miniflux API {method} {path} returned HTTP {response.status}"
            )
        return json.loads(content) if content else None
    finally:
        connection.close()


def import_feeds(
    base_url: str, username: str, password: str, feeds: list[dict], pending: Path
):
    auth = base64.b64encode(f"{username}:{password}".encode()).decode()
    user = api(base_url, auth, "GET", "/v1/me")
    api(
        base_url,
        auth,
        "PUT",
        f"/v1/users/{user['id']}",
        {
            "entry_sorting_direction": "desc",
            "theme": "system_sans_serif",
            "entries_per_page": 30,
            "show_reading_time": True,
            "keyboard_shortcuts": True,
            "entry_swipe": True,
        },
    )
    categories = {
        category["title"]: category["id"]
        for category in api(base_url, auth, "GET", "/v1/categories")
    }
    existing = {
        feed["feed_url"]: feed["id"] for feed in api(base_url, auth, "GET", "/v1/feeds")
    }
    interrupted = (
        json.loads(pending.read_text(encoding="utf-8")) if pending.exists() else {}
    )
    for feed in feeds:
        category_name = feed["category"]
        if category_name not in categories:
            category = api(
                base_url,
                auth,
                "POST",
                "/v1/categories",
                {"title": category_name},
            )
            categories[category_name] = category["id"]
        if feed["url"] in existing and interrupted.get("url") != feed["url"]:
            continue
        if feed["url"] not in existing:
            # Persist ownership before POST so an interrupted response or PUT
            # can resume without reconciling arbitrary existing subscriptions.
            save_progress(pending, {"url": feed["url"]})
            created = api(
                base_url,
                auth,
                "POST",
                "/v1/feeds",
                {
                    "feed_url": feed["url"],
                    "category_id": categories[category_name],
                    "crawler": False,
                },
            )
            existing[feed["url"]] = created["feed_id"]
        api(
            base_url,
            auth,
            "PUT",
            f"/v1/feeds/{existing[feed['url']]}",
            {
                "crawler": feed.get("crawler", False),
                "rewrite_rules": feed.get("rewriteRules", ""),
                "scraper_rules": feed.get("scraperRules", ""),
            },
        )
        pending.unlink(missing_ok=True)


class ArticleText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def word_count(content):
    parser = ArticleText()
    parser.feed(content)
    return len(" ".join(parser.parts).split())


def save_progress(path, progress):
    temporary = path.with_name(path.name + f".partial.{os.getpid()}")
    temporary.write_text(json.dumps(progress), encoding="utf-8")
    temporary.replace(path)


SHORT_ARTICLE_WORDS = 350
MINIMUM_REPAIR_WORDS = 180
MAX_REPAIR_ATTEMPTS = 3


def configure_reader(request, policy):
    feeds = {feed["feed_url"]: feed for feed in request("GET", "/v1/feeds")}
    candidates = []
    for desired in policy["feeds"]:
        current = feeds.get(desired["url"])
        # Deleted and manually disabled subscriptions remain user-owned.
        if current is None or current["disabled"]:
            continue
        changes = {"crawler": desired.get("crawler", False)}
        # Custom publisher rules may encode deliberate user repairs.
        for api_key, policy_key in (
            ("rewrite_rules", "rewriteRules"),
            ("scraper_rules", "scraperRules"),
        ):
            if not current.get(api_key):
                changes[api_key] = desired.get(policy_key, "")
        request("PUT", f"/v1/feeds/{current['id']}", changes)
        if changes["crawler"] and policy["backfillLimit"]:
            entries = request(
                "GET",
                f"/v1/feeds/{current['id']}/entries?status=unread&order=published_at"
                f"&direction=desc&limit={policy['backfillLimit']}",
            )["entries"]
            candidates.extend(
                e["id"]
                for e in entries
                if word_count(e["content"]) < SHORT_ARTICLE_WORDS
            )
    for url in policy["disabledFeeds"]:
        if url in feeds and not feeds[url]["disabled"]:
            request("PUT", f"/v1/feeds/{feeds[url]['id']}", {"disabled": True})
    user = request("GET", "/v1/me")
    # User styles take precedence. Never replace an existing stylesheet.
    if policy["stylesheet"] and not (user.get("stylesheet") or "").strip():
        request("PUT", f"/v1/users/{user['id']}", {"stylesheet": policy["stylesheet"]})
    return {
        "configured": True,
        "pending": list(dict.fromkeys(candidates)),
        "updated": 0,
        "skipped": 0,
        "failed": 0,
    }


def restore_publisher_urls(content, public_url):
    # fetch-content returns display HTML containing Miniflux proxy URLs. PUT
    # expects publisher HTML; storing display URLs would proxy them a second
    # time and make images depend on a particular server URL and signing key.
    pattern = (
        re.escape(public_url.rstrip("/"))
        + r"/proxy/[A-Za-z0-9_-]+=*/([A-Za-z0-9_-]+=*)"
    )

    def original(match):
        try:
            url = base64.b64decode(match[1], altchars=b"-_", validate=True).decode()
            if urlsplit(url).scheme not in {"http", "https"}:
                return match[0]
            return html.escape(url, quote=True)
        except ValueError, UnicodeDecodeError:
            return match[0]

    return re.sub(pattern, original, content)


def repair_entry(request, entry_id, public_url):
    entry = request("GET", f"/v1/entries/{entry_id}")
    old_words = word_count(entry["content"])
    if entry["status"] != "unread" or old_words >= SHORT_ARTICLE_WORDS:
        return "skipped"
    content = request(
        "GET", f"/v1/entries/{entry_id}/fetch-content?update_content=false"
    )["content"]
    # Keep the original on empty, shorter or obvious teaser results.
    # This is a conservative repair gate, not an editorial score.
    if word_count(content) < max(MINIMUM_REPAIR_WORDS, old_words * 1.4):
        return "skipped"
    request(
        "PUT",
        f"/v1/entries/{entry_id}",
        {"content": restore_publisher_urls(content, public_url)},
    )
    return "updated"


def upgrade_reader(base_url, username, password, policy, state):
    progress = json.loads(state.read_text()) if state.exists() else {}
    if progress.get("complete"):
        return progress
    auth = base64.b64encode(f"{username}:{password}".encode()).decode()

    def request(method, path, payload=None):
        return api(base_url, auth, method, path, payload)

    if not progress.get("configured"):
        progress = configure_reader(request, policy)
        save_progress(state, progress)
    attempts = progress.setdefault("attempts", {})
    for entry_id in list(progress["pending"]):
        try:
            outcome = repair_entry(request, entry_id, policy["publicUrl"])
        except RuntimeError, OSError, http.client.HTTPException:
            # Retain transient failures across bounded service retries. Never
            # log URLs, credentials, response bodies or article titles.
            key = str(entry_id)
            attempts[key] = attempts.get(key, 0) + 1
            if attempts[key] < MAX_REPAIR_ATTEMPTS:
                save_progress(state, progress)
                continue
            outcome = "failed"
        progress[outcome] += 1
        progress["pending"].remove(entry_id)
        save_progress(state, progress)
    if progress["pending"]:
        raise RuntimeError("Miniflux content upgrade has pending retries")
    progress["complete"] = True
    save_progress(state, progress)
    sys.stdout.write(
        "Miniflux content upgrade: "
        + json.dumps({key: progress[key] for key in ("updated", "skipped", "failed")})
        + "\n"
    )
    return progress


def main():
    if sys.argv[1] == "--upgrade":
        upgrade_reader(
            os.environ["MINIFLUX_BOOTSTRAP_URL"],
            os.environ["ADMIN_USERNAME"],
            os.environ["ADMIN_PASSWORD"],
            json.loads(Path(sys.argv[2]).read_text(encoding="utf-8")),
            Path(os.environ["MINIFLUX_UPGRADE_STATE"]),
        )
        return
    marker = Path(os.environ["MINIFLUX_BOOTSTRAP_MARKER"])
    if marker.exists():
        return
    feeds = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    import_feeds(
        os.environ["MINIFLUX_BOOTSTRAP_URL"],
        os.environ["ADMIN_USERNAME"],
        os.environ["ADMIN_PASSWORD"],
        feeds,
        marker.with_name("initial-feed-pending.json"),
    )
    temporary = marker.with_name(marker.name + f".partial.{os.getpid()}")
    temporary.write_text(
        "Initial feeds imported. Later changes are user-owned.\n", encoding="utf-8"
    )
    temporary.replace(marker)


if __name__ == "__main__":
    main()
