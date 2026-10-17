#!/usr/bin/env python3
"""Generate with the latest stable MultiworldGG, without running a public server."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from urllib.request import Request, urlopen

REPOSITORY = "MultiworldGG/MultiworldGG"
LATEST = f"https://api.github.com/repos/{REPOSITORY}/releases/latest"


def latest_release() -> str:
    request = Request(LATEST, headers={"Accept": "application/vnd.github+json",
                                      "User-Agent": "Pathogenic-MultiworldGG"})
    with urlopen(request, timeout=60) as response:
        release = json.load(response)
    if not isinstance(release, dict) or release.get("draft") is not False \
            or release.get("prerelease") is not False:
        raise ValueError("GitHub did not return a stable MultiworldGG release")
    tag = release.get("tag_name")
    if not isinstance(tag, str) or not re.fullmatch(r"v?\d+\.\d+\.\d+", tag):
        raise ValueError("Invalid MultiworldGG release tag")
    return tag


def prepare_runtime(directory: Path, tag: str) -> Path:
    runtime = directory / f".multiworldgg-{tag}"
    if runtime.is_symlink():
        raise ValueError(f"Refusing a symlinked runtime: {runtime}")
    if not runtime.exists():
        with tempfile.TemporaryDirectory(prefix=".multiworldgg-download-", dir=directory) as temporary:
            staging = Path(temporary)
            archive = staging / "source.tar.gz"
            url = f"https://github.com/{REPOSITORY}/archive/refs/tags/{tag}.tar.gz"
            print(f"Downloading MultiworldGG {tag}...", flush=True)
            with urlopen(url, timeout=120) as incoming, archive.open("wb") as outgoing:
                shutil.copyfileobj(incoming, outgoing)
            extracted = staging / "source"
            extracted.mkdir()
            with tarfile.open(archive) as source:
                source.extractall(extracted, filter="data")
            roots = list(extracted.iterdir())
            if len(roots) != 1 or not (roots[0] / "Generate.py").is_file() \
                    or not (roots[0] / "ModuleUpdate.py").is_file():
                raise ValueError("MultiworldGG download does not contain a generator")
            roots[0].rename(runtime)
    for name in ("Generate.py", "ModuleUpdate.py"):
        if not (runtime / name).is_file():
            raise ValueError(f"Incomplete runtime at {runtime}; inspect it before retrying")
    python = runtime / ".venv/bin/python"
    if not python.is_file():
        subprocess.run([sys.executable, "-m", "venv", str(runtime / ".venv")], check=True)
    return runtime


def generate(directory: Path) -> Path:
    directory = directory.resolve(strict=True)
    yamls = sorted([*directory.glob("*.yaml"), *directory.glob("*.yml")])
    if not yamls:
        raise ValueError(f"Put player YAML files in {directory}")
    tag = latest_release()
    print(f"Using latest stable MultiworldGG {tag}", flush=True)
    runtime = prepare_runtime(directory, tag)
    custom = runtime / "custom_worlds"
    if custom.is_symlink():
        raise ValueError(f"Refusing symlinked custom_worlds: {custom}")
    custom.mkdir(exist_ok=True)
    # This cache's custom_worlds contains only this invocation's supplied worlds.
    for previous in custom.glob("*.apworld"):
        previous.unlink()
    for world in directory.glob("*.apworld"):
        shutil.copy2(world, custom / world.name)
    # Include this invocation's custom-world dependencies, and retry interrupted setup.
    subprocess.run([str(runtime / ".venv/bin/python"), "ModuleUpdate.py", "--yes"],
                   cwd=runtime, check=True)
    output = directory / "output"
    output.mkdir(exist_ok=True)
    previous_archives = {path: path.stat().st_mtime_ns for path in output.glob("AP_*.zip")}
    with tempfile.TemporaryDirectory(prefix="players-", dir=runtime) as temporary:
        players = Path(temporary)
        for yaml in yamls:
            shutil.copy2(yaml, players / yaml.name)
        subprocess.run(
            [str(runtime / ".venv/bin/python"), "Generate.py",
             "--player_files_path", str(players), "--outputpath", str(output)],
            cwd=runtime, stdin=subprocess.DEVNULL, check=True,
            env={**os.environ, "SKIP_REQUIREMENTS_UPDATE": "1"},
        )
    archives = [path for path in output.glob("AP_*.zip")
                if previous_archives.get(path) != path.stat().st_mtime_ns]
    if len(archives) != 1:
        raise ValueError("Generator did not produce exactly one new AP_*.zip; inspect its output")
    archive = archives[0]
    (output / "generation.json").write_text(
        json.dumps({"release": tag, "archive": archive.name}, indent=2) + "\n"
    )
    print(f"Generated with MultiworldGG {tag}: {archive}\n"
          "Upload only this ZIP at https://multiworld.gg/uploads, create a room,\n"
          "then copy its WebSocket endpoint into Settings > MultiworldGG.", flush=True)
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    try:
        generate(args.directory)
    except (OSError, ValueError, tarfile.TarError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"MultiworldGG generation failed: {error}\n")
