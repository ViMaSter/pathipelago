#!/usr/bin/env python3
"""Build a private modded app from the user's verified installation, never redistribute it."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import zipfile

from install import verify_game

ROOT = Path(__file__).resolve().parents[1]
USER_DIR = "Pathogenic Archipelago"
LAUNCHER_HEADER = "#!/bin/bash\n# Pathogenic Archipelago generated launcher v1\n"


def project_config(text: str, user_dir: str = USER_DIR) -> str:
    if re.findall(r"^initialization/app_id=.*$", text, re.MULTILINE) != [
        "initialization/app_id=4029380"
    ]:
        raise ValueError("Recovered configuration does not identify the demo")
    if text.count("[autoload]") != 1 or text.count("[application]") != 1:
        raise ValueError("Unexpected project configuration sections")
    if "ArchipelagoBootstrap=" in text:
        raise ValueError("Original project already has an AP bootstrap")
    if re.search(r"^config/(use_custom_user_dir|custom_user_dir_name)=", text, re.MULTILINE):
        raise ValueError("Original project already overrides its save directory")
    if not re.fullmatch(r"[A-Za-z0-9 _-]+", user_dir):
        raise ValueError("Save directory must be a single safe directory name")
    text = text.replace(
        "[autoload]", '[autoload]\nArchipelagoBootstrap="*res://archipelago_bootstrap.gd"', 1
    )
    text = text.replace(
        "[application]",
        '[application]\nconfig/use_custom_user_dir=true\n'
        f'config/custom_user_dir_name={json.dumps(user_dir)}',
        1,
    )
    # Do not send mod diagnostics or AP connection metadata to the game's telemetry.
    text, count = re.subn(r'^options/dsn=.*$', 'options/dsn=""', text, flags=re.MULTILINE)
    if count != 1:
        raise ValueError("Cannot disable the original telemetry endpoint")
    return text


def run(command: list[str], log: Path) -> None:
    print(f"Build log: {log}", flush=True)
    with log.open("w") as output:
        subprocess.run(command, check=True, stdout=output, stderr=subprocess.STDOUT, timeout=300)


def check_launcher(launcher: Path) -> None:
    if launcher.is_symlink():
        raise ValueError("Refusing a symlinked launcher")
    if launcher.exists() and (
        not launcher.is_file() or not launcher.read_text().startswith(LAUNCHER_HEADER)
    ):
        raise ValueError("Refusing to replace an unowned launcher")


def write_launcher(launcher: Path, executable: Path) -> None:
    check_launcher(launcher)
    with tempfile.NamedTemporaryFile(mode="w", prefix=".ap-launcher-", dir=launcher.parent,
                                     delete=False) as output:
        stage = Path(output.name)
        output.write(LAUNCHER_HEADER + "set -euo pipefail\n"
                     f"exec {shlex.quote(str(executable))} \"$@\"\n")
        output.flush()
        os.fsync(output.fileno())
    try:
        stage.chmod(0o755)
        check_launcher(launcher)
        stage.replace(launcher)
    finally:
        stage.unlink(missing_ok=True)


def smoke_test(app: Path, log: Path) -> None:
    executable = app / "Contents/MacOS/Pathogenic"
    print(f"Native bootstrap test log: {log}", flush=True)
    with log.open("w") as output:
        result = subprocess.run(
            [str(executable), "--headless", "--", "--ap-smoke-test"],
            stdout=output, stderr=subprocess.STDOUT, timeout=60,
        )
    text = log.read_text(errors="replace")
    expected = (
        f"AP_BOOTSTRAP_SMOKE user_dir={Path.home() / 'Library/Application Support' / USER_DIR}"
        " extended=true scene_extended=true client=true"
    )
    if result.returncode or "SCRIPT ERROR:" in text or expected not in text:
        raise RuntimeError(f"Native bootstrap validation failed; inspect {log}. Launcher unchanged.")


def build_demo(game: Path, gdre: Path) -> Path:
    game = verify_game(game)
    if not gdre.is_file():
        raise ValueError("GDRE Tools executable is required; supply --gdre")
    launcher = ROOT / "launch-modded.command"
    check_launcher(launcher)
    archive = ROOT / "dist/Local-ArchipelagoShop.zip"
    with zipfile.ZipFile(archive) as packed:
        if packed.testzip() is not None:
            raise ValueError("Built mod archive is corrupt")
    builds = ROOT / "local-builds"
    if builds.is_symlink():
        raise ValueError("Refusing a symlinked local-builds directory")
    builds.mkdir(exist_ok=True)
    # Retain earlier builds rather than deleting a possibly running app or user files.
    output = Path(tempfile.mkdtemp(prefix="demo-ap-", dir=builds))
    app = output / "Pathogenic AP.app"
    marker = {
        "source_app": str(game), "app": str(app), "status": "incomplete",
        "save_directory": str(Path.home() / "Library/Application Support" / USER_DIR),
        "warning": "PRIVATE LOCAL GAME COPY: do not distribute",
    }
    metadata = output / "build.json"
    metadata.write_text(json.dumps(marker, indent=2) + "\n")
    original_pack = game / "Contents/Resources/Pathogenic.pck"
    with tempfile.TemporaryDirectory(prefix="pathogenic-ap-config-") as temporary:
        work = Path(temporary)
        recovered = work / "recovered"
        run([str(gdre), "--headless", f"--recover={original_pack}",
             "--include=res://project.binary", f"--output={recovered}"], output / "recovery.log")
        config = work / "project.godot"
        config.write_text(project_config((recovered / "project.godot").read_text()))
        shutil.copytree(game, app, ignore=shutil.ignore_patterns("Pathogenic.pck"))
        resources = app / "Contents/Resources"
        copied_mod = resources / archive.name
        shutil.copy2(archive, copied_mod)
        if archive.read_bytes() != copied_mod.read_bytes():
            raise RuntimeError("Copied mod archive differs from built archive")
        pack = resources / "Pathogenic.pck"
        run([str(gdre), "--headless", f"--pck-patch={original_pack}", f"--output={pack}",
             "--exclude=res://project.binary", "--exclude=res://project.godot",
             f"--patch-file={config}=res://project.godot",
             f"--patch-file={ROOT / 'bootstrap.gd'}=res://archipelago_bootstrap.gd"],
            output / "pack.log")
    smoke_test(app, output / "native-smoke.log")
    # Recheck the source after copying and patching: Steam updates must fail closed.
    verify_game(game)
    marker["status"] = "native-bootstrap-verified"
    for key, path in (("mod_sha256", copied_mod), ("patched_pck_sha256", pack)):
        with path.open("rb") as source:
            marker[key] = hashlib.file_digest(source, "sha256").hexdigest()
    metadata.write_text(json.dumps(marker, indent=2) + "\n")
    write_launcher(launcher, app / "Contents/MacOS/Pathogenic")
    print(f"Local modded app: {app}\nLauncher: {launcher}")
    print(f"Separate saves: {marker['save_directory']}")
    return app


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("game", type=Path)
    parser.add_argument("--gdre", type=Path, required=True)
    args = parser.parse_args()
    build_demo(args.game, args.gdre)
