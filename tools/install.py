#!/usr/bin/env python3
"""Replace only an owned mod; never remove saves, other mods, or official files."""

import hashlib
from pathlib import Path
import shutil
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MOD_NAME = "Local-ArchipelagoShop.zip"
EXECUTABLE_SHA256 = "0bf53c05712a1d60f54dbeb387d7f059c27cb94e08690bff067ee202b53e0370"
PCK_SHA256 = "8396febf677a23708da11dafe0deed353c2c2cb0709566eb725d0e2632c93ea4"


def verify_game(game: Path) -> Path:
    game = game.resolve(strict=True)
    executable = game / "Contents" / "MacOS" / "Pathogenic"
    for path, expected in (
        (executable, EXECUTABLE_SHA256),
        (game / "Contents/Resources/Pathogenic.pck", PCK_SHA256),
    ):
        with path.open("rb") as source_file:
            actual = hashlib.file_digest(source_file, "sha256").hexdigest()
        if actual != expected:
            raise ValueError(
                "Unsupported game files: expected demo build 25697109. "
                "No game files were changed. Re-investigate after a Steam update."
            )
    return game


def install(game: Path) -> Path:
    game = verify_game(game)
    mods = game.parent / "mods"
    if mods.is_symlink():
        raise ValueError("Refusing a symlinked mods directory")
    mods.mkdir(exist_ok=True)
    destination = mods / MOD_NAME
    unpacked = game.parent / "mods-unpacked" / "Local-ArchipelagoShop"
    if unpacked.exists():
        raise ValueError(f"Conflicting unpacked copy exists; inspect it manually: {unpacked}")
    source = ROOT / "dist" / MOD_NAME
    if destination.is_symlink():
        raise ValueError("Refusing a symlinked mod installation")
    if destination.exists():
        with zipfile.ZipFile(destination) as previous:
            import json
            manifest = json.loads(
                previous.read("mods-unpacked/Local-ArchipelagoShop/manifest.json")
            )
            if manifest.get("namespace") != "Local" or manifest.get("name") != "ArchipelagoShop":
                raise ValueError("Existing mod is not owned by this project")
        backup = ROOT / "dist" / "previous-install.zip"
        shutil.copy2(destination, backup)
        print(f"Preserved previous owned installation: {backup}")
    temporary = mods / (MOD_NAME + ".installing")
    if temporary.exists() or temporary.is_symlink():
        raise ValueError(f"Stale installation staging file exists; inspect manually: {temporary}")
    created = False
    try:
        with source.open("rb") as incoming, temporary.open("xb") as outgoing:
            created = True
            shutil.copyfileobj(incoming, outgoing)
            outgoing.flush()
            import os
            os.fsync(outgoing.fileno())
        with zipfile.ZipFile(temporary) as packed:
            if packed.testzip() is not None:
                raise ValueError("Mod archive integrity check failed")
        if source.read_bytes() != temporary.read_bytes():
            raise ValueError("Installed bytes do not match built archive")
        temporary.replace(destination)
    finally:
        if created and temporary.exists() and not temporary.is_symlink():
            temporary.unlink()
    print(f"Installed and byte-verified: {destination}")
    print("Cleaned/replaced only this mod's ZIP. Official PCK, saves and other mods untouched.")
    return destination


if __name__ == "__main__":
    raise SystemExit(
        "The demo disables Mod Loader. Use build-install.sh --gdre /path/to/GDRE "
        "to build a verified private app instead of installing an inactive ZIP."
    )
