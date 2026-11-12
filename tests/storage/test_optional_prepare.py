"""Exercise the optional storage command with empty and nonempty outputs."""

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

TEMPLATE = (
    Path(__file__).parents[2]
    / "modules/optional/scripts/prepare-application-storage.sh"
)
PREPARE = Path(__file__).parents[2] / "scripts/storage/prepare.py"


def render(tmp_path: Path, paths: list[str], helper: Path) -> Path:
    python = tmp_path / "python" / "bin" / "python3"
    python.parent.mkdir(parents=True)
    python.symlink_to(sys.executable)
    source = TEMPLATE.read_text()
    replacements = {
        "pkgs_python3": shlex.quote(str(python.parent.parent)),
        "scripts_storage_prepare_py": shlex.quote(str(helper)),
        "lib_escapeShellArg_storage_group": "fixture-group",
        "lib_escapeShellArgs_guardedDirs": shlex.join(paths),
    }
    for name, value in replacements.items():
        source = source.replace(f"@{name}@", value)
    script = tmp_path / "prepare.sh"
    script.write_text(source)
    return script


def execute(script: Path, **environment: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [os.environ["BASH_PROGRAM"], "-e", str(script)],
        env=os.environ | environment,
        capture_output=True,
        text=True,
        check=False,
    )


def test_no_optional_outputs_do_not_invoke_strict_preparer(tmp_path: Path) -> None:
    """An empty optional output list succeeds without looking up a group."""
    result = execute(render(tmp_path, [], PREPARE))
    assert result.returncode == 0, result.stderr
    assert not result.stdout
    assert not result.stderr


def test_optional_paths_keep_exact_arguments(tmp_path: Path) -> None:
    """Pass each selected path intact, including shell metacharacters."""
    helper = tmp_path / "capture.py"
    helper.write_text(
        "import json, os, sys\n"
        "open(os.environ['CAPTURE'], 'w').write(json.dumps(sys.argv[1:]))\n"
    )
    capture = tmp_path / "arguments.json"
    paths = ["/srv/media/space and quote'", "/srv/media/$literal;command"]
    result = execute(render(tmp_path, paths, helper), CAPTURE=str(capture))
    assert result.returncode == 0, result.stderr
    assert json.loads(capture.read_text()) == ["fixture-group", *paths]


def test_optional_preparation_failure_remains_fatal(tmp_path: Path) -> None:
    """Preserve the helper's failure so dependent services cannot start."""
    helper = tmp_path / "fail.py"
    helper.write_text("raise SystemExit(23)\n")
    result = execute(render(tmp_path, ["/srv/media/output"], helper))
    assert result.returncode == 23
