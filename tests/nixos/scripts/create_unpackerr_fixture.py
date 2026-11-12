"""Create the ZIP permission fixture used by the optional-media VM test."""

from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import ZipFile, ZipInfo


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    args.directory.mkdir()
    info = ZipInfo("fixture.txt")
    info.external_attr = 0o660 << 16
    with ZipFile(args.directory / "fixture.zip", "w") as archive:
        archive.writestr(info, "permitted fixture media")


if __name__ == "__main__":
    main()
