"""Check credential and feed read failures before FreshRSS account operations."""

import os
import pathlib
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]


@pytest.mark.parametrize(
    ("script", "username_argument", "has_username", "expected"),
    [
        ("provision-freshrss-user.php", None, False, "runtime username"),
        ("provision-freshrss-user.php", None, True, "runtime password"),
        ("bootstrap-freshrss.php", "--username-credential", False, "runtime username"),
        ("bootstrap-freshrss.php", "runtime-reader", False, "starter feed list"),
    ],
)
def test_failed_read(
    tmp_path: pathlib.Path,
    script: str,
    username_argument: str | None,
    *,
    has_username: bool,
    expected: str,
) -> None:
    """Refuse unavailable inputs with an explicit error instead of a TypeError."""
    php = os.environ.get("PHP_TEST_EXECUTABLE")
    if php is None:
        pytest.skip("The php-read-failures Nix check supplies the PHP interpreter.")
    cli = tmp_path / "app" / "cli"
    cli.mkdir(parents=True)
    (cli / "_cli.php").write_text(
        "<?php\n"
        "function cliInitUser(string $name): void {}\n"
        "function fail(string $message): never { throw new RuntimeException($message); }\n",
        encoding="utf-8",
    )
    credentials = tmp_path / "credentials"
    credentials.mkdir()
    if has_username:
        (credentials / "news-username").write_text("runtime-reader\n", encoding="utf-8")
    environment = os.environ | {
        "FRESHRSS_PACKAGE": str(cli.parent),
        "CREDENTIALS_DIRECTORY": str(credentials),
    }
    arguments = (
        []
        if username_argument is None
        else [
            username_argument,
            str(tmp_path / "missing-feeds.json"),
            str(tmp_path / "marker"),
        ]
    )
    result = subprocess.run(
        [php, "-n", str(ROOT / "scripts" / "optional" / script), *arguments],
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    diagnostic = result.stdout + result.stderr
    assert result.returncode != 0
    assert expected in diagnostic
    assert "TypeError" not in diagnostic
