#!/usr/bin/env python3
"""Install the built mod ZIP into the full game's local mods folder for development.

Replaces only this project's own ZIP; never removes saves, other mods or official files.
Players should subscribe on the Steam Workshop instead.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MOD_ID = "ViMaSter-MultiworldGGShop"
MOD_NAME = f"{MOD_ID}.zip"
LEGACY_MOD_ID = "ViMaSter-ArchipelagoShop"
APP_ID = "3808690"
DEFAULT_GAME = Path.home() / "Library/Application Support/Steam/steamapps/common/Pathogenic/Pathogenic.app"


def verify_game(game: Path) -> Path:
    game = game.resolve(strict=True)
    if not (game / "Contents/Resources/Pathogenic.pck").is_file():
        raise ValueError(f"Not a Pathogenic app bundle: {game}")
    steam_data = game.parent / "steam_data.json"
    try:
        app_id = str(json.loads(steam_data.read_text()).get("app_id"))
    except (OSError, ValueError) as error:
        raise ValueError(f"Cannot read {steam_data}: {error}") from error
    if app_id != APP_ID:
        raise ValueError(
            f"Expected the full game (Steam app {APP_ID}), found app {app_id}. "
            "The demo does not load mods."
        )
    return game


def workshop_copy(game: Path) -> Path | None:
    workshop = game.parent.parent.parent / "workshop/content" / APP_ID
    return next(workshop.glob(f"*/{MOD_NAME}"), None) if workshop.is_dir() else None


def install(game: Path) -> Path:
    game = verify_game(game)
    mods = game.parent / "mods"
    if mods.is_symlink():
        raise ValueError("Refusing a symlinked mods directory")
    legacy = [mods / f"{LEGACY_MOD_ID}.zip", game.parent / "mods-unpacked" / LEGACY_MOD_ID]
    workshop = game.parent.parent.parent / "workshop/content" / APP_ID
    legacy.extend(workshop.glob(f"*/{LEGACY_MOD_ID}.zip"))
    for path in legacy:
        if path.exists() or path.is_symlink():
            raise ValueError(f"Legacy Archipelago mod would load alongside MultiworldGG; "
                             f"remove or update it manually before installing: {path}")
    mods.mkdir(exist_ok=True)
    destination = mods / MOD_NAME
    unpacked = game.parent / "mods-unpacked" / MOD_ID
    if unpacked.exists():
        raise ValueError(f"Conflicting unpacked copy exists; inspect it manually: {unpacked}")
    source = ROOT / "dist" / MOD_NAME
    if destination.is_symlink():
        raise ValueError("Refusing a symlinked mod installation")
    if destination.exists():
        with zipfile.ZipFile(destination) as previous:
            manifest = json.loads(previous.read(f"mods-unpacked/{MOD_ID}/manifest.json"))
            if f"{manifest.get('namespace')}-{manifest.get('name')}" != MOD_ID:
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
    print("Replaced only this mod's ZIP. Official PCK, saves and other mods untouched.")
    subscribed = workshop_copy(game)
    if subscribed:
        print(f"WARNING: the Workshop copy is also subscribed ({subscribed}). "
              "Unsubscribe or remove the local ZIP so only one version loads.")
    return destination


def uninstall(game: Path) -> None:
    destination = verify_game(game).parent / "mods" / MOD_NAME
    if destination.is_symlink() or not destination.is_file():
        print(f"Nothing to remove: {destination}")
        return
    destination.unlink()
    print(f"Removed only {destination}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME, help="Path to Pathogenic.app")
    parser.add_argument("--uninstall", action="store_true")
    args = parser.parse_args()
    uninstall(args.game) if args.uninstall else install(args.game)
