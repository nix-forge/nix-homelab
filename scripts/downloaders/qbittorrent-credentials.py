"""Validate the small qBittorrent WebUI credential fragment."""

import configparser
import sys
from pathlib import Path
from typing import override

ALLOWED_KEYS = {"WebUI\\Username", "WebUI\\Password_PBKDF2"}
EXPECTED_ARGUMENTS = 3


class CaseSensitiveConfigParser(configparser.ConfigParser):
    @override
    def optionxform(self, optionstr):
        return optionstr


def read_fragment(source):
    parser = CaseSensitiveConfigParser(
        interpolation=None,
        strict=True,
        delimiters=("=",),
        comment_prefixes=(),
    )
    try:
        parser.read_string(source.read_text(encoding="utf-8"))
    except (OSError, configparser.Error) as error:
        raise ValueError("invalid qBittorrent credential fragment") from error
    if parser.defaults() or parser.sections() != ["Preferences"]:
        raise ValueError("qBittorrent credentials may contain only [Preferences]")
    values = dict(parser["Preferences"])
    if set(values) != ALLOWED_KEYS or any(
        "\n" in value or "\r" in value for value in values.values()
    ):
        raise ValueError(
            "qBittorrent credentials must contain only WebUI username and password"
        )
    return values


def write_fragment(target, values):
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".tmp")
    try:
        temporary.write_text(
            "[Preferences]\n"
            + "\n".join(f"{key}={values[key]}" for key in sorted(values))
            + "\n",
            encoding="utf-8",
        )
        temporary.chmod(0o600)
        temporary.replace(target)
    except OSError as error:
        temporary.unlink(missing_ok=True)
        raise ValueError("could not write validated qBittorrent credentials") from error


def main():
    if len(sys.argv) != EXPECTED_ARGUMENTS:
        return 2
    try:
        write_fragment(Path(sys.argv[2]), read_fragment(Path(sys.argv[1])))
    except ValueError as error:
        sys.stderr.write(f"{error}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
