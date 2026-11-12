"""Set declared Moonbase options and preserve other saved settings."""

import os
import pathlib
import sys
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET


def local_name(tag):
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else None


def configure(  # ruff: ignore[complex-structure,too-many-branches] - preserve existing plugin XML fields and comments
    path, seerr_url
):
    parsed_url = urllib.parse.urlparse(seerr_url)
    if (
        parsed_url.scheme not in {"http", "https"}
        or not parsed_url.netloc
        or any((
            parsed_url.username,
            parsed_url.password,
            parsed_url.query,
            parsed_url.fragment,
        ))
    ):
        raise ValueError("Seerr URL must be an absolute HTTP or HTTPS URL")

    if path.is_symlink():
        raise ValueError("Moonbase configuration must be a regular file")

    if path.exists():
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        root = ET.parse(path, parser=parser).getroot()
        if local_name(root.tag) != "PluginConfiguration":
            raise ValueError("unexpected Moonbase configuration root element")
    else:
        root = ET.Element("PluginConfiguration")

    namespace = ""
    if root.tag.startswith("{"):
        namespace = root.tag.partition("}")[0] + "}"
    changed = not path.exists()
    for name, value in (
        ("EnableSettingsSync", "true"),
        ("SeerrEnabled", "true"),
        ("SeerrUrl", seerr_url),
        ("GamesIsolateWebApp", "true"),
    ):
        matches = [child for child in root if local_name(child.tag) == name]
        if len(matches) > 1:
            raise ValueError(f"duplicate Moonbase configuration field: {name}")
        if matches:
            field = matches[0]
            for attribute in list(field.attrib):
                if local_name(attribute) == "nil":
                    del field.attrib[attribute]
                    changed = True
            if field.text != value:
                field.text = value
                changed = True
        else:
            ET.SubElement(root, f"{namespace}{name}").text = value
            changed = True

    if not changed:
        return

    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    payload = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary_path = pathlib.Path(stream.name)
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        temporary_path.chmod(0o600)
        temporary_path.replace(path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    configure(pathlib.Path(sys.argv[1]), sys.argv[2])
