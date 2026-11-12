"""Moonbase's managed Seerr settings preserve its other server data."""

import importlib.util
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/media/configure_moonbase.py"
SPEC = importlib.util.spec_from_file_location("configure_moonbase", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def test_enables_seerr_without_losing_existing_configuration(tmp_path):
    config = tmp_path / "Moonfin.Server.xml"
    config.write_text(
        '<PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        "<EnableSettingsSync>false</EnableSettingsSync>"
        "<SeerrEnabled>false</SeerrEnabled>"
        '<SeerrUrl xsi:nil="true" />'
        "<SeerrWebhookSecret>existing-secret</SeerrWebhookSecret>"
        "<MdblistApiKey>existing-key</MdblistApiKey>"
        "</PluginConfiguration>"
    )

    MODULE.configure(config, "http://127.0.0.1:5055")

    fields = {child.tag: child.text for child in ET.parse(config).getroot()}
    assert fields == {
        "EnableSettingsSync": "true",
        "SeerrEnabled": "true",
        "SeerrWebhookSecret": "existing-secret",
        "MdblistApiKey": "existing-key",
        "SeerrUrl": "http://127.0.0.1:5055",
        "GamesIsolateWebApp": "true",
    }
    seerr_url = ET.parse(config).getroot().find("SeerrUrl")
    assert seerr_url is not None
    assert not seerr_url.attrib
    assert config.stat().st_mode & 0o777 == 0o600
    inode = config.stat().st_ino
    MODULE.configure(config, "http://127.0.0.1:5055")
    assert config.stat().st_ino == inode


def test_invalid_existing_configuration_is_not_replaced(tmp_path):
    config = tmp_path / "Moonfin.Server.xml"
    config.write_text("<PluginConfiguration><SeerrEnabled>")

    with pytest.raises(ET.ParseError):
        MODULE.configure(config, "http://127.0.0.1:5055")

    assert config.read_text() == "<PluginConfiguration><SeerrEnabled>"


@pytest.mark.parametrize(
    "url",
    [
        "http://user:password@127.0.0.1:5055",
        "http://127.0.0.1:5055/?token=fixture",
        "http://127.0.0.1:5055/#fixture",
    ],
)
def test_rejects_credential_bearing_urls(tmp_path, url):
    config = tmp_path / "Moonfin.Server.xml"

    with pytest.raises(ValueError, match="Seerr URL"):
        MODULE.configure(config, url)

    assert not config.exists()
