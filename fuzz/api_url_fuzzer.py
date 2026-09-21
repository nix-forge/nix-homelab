"""Fuzz the URL policy that confines integration clients to safe endpoints."""

import ipaddress
import sys
import urllib.parse
from pathlib import Path

import atheris

MAX_INPUT_SIZE = 1024
CONTROL_CHAR_LIMIT = 32
MAX_PORT = 65535

with atheris.instrument_imports():
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/integration"))
    from common import ConfigurationError, validate_url


def check(value: str) -> None:
    try:
        accepted = validate_url(value)
    except ConfigurationError:
        return
    assert accepted == value.rstrip("/")
    assert all(ord(char) >= CONTROL_CHAR_LIMIT for char in accepted)
    parts = urllib.parse.urlsplit(accepted)
    assert parts.scheme in {"http", "https"}
    assert parts.hostname
    assert not parts.username
    assert not parts.password
    assert not parts.query
    assert not parts.fragment
    assert parts.port is None or 0 <= parts.port <= MAX_PORT
    if parts.scheme == "http":
        try:
            assert ipaddress.ip_address(parts.hostname).is_loopback
        except ValueError:
            assert parts.hostname == "localhost"


@atheris.instrument_func
def test_one_input(data: bytes) -> None:
    if len(data) > MAX_INPUT_SIZE:
        return
    value = data.decode("utf-8", errors="replace")
    for candidate in (
        value,
        f"http://{value}",
        f"https://{value}",
        f"http://localhost/{value}",
    ):
        check(candidate)


if __name__ == "__main__":
    atheris.Setup(sys.argv, test_one_input)
    atheris.Fuzz()
