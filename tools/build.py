#!/usr/bin/env python3
"""Build reproducible archives containing only this project's original source."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MOD_ID = "ViMaSter-MultiworldGGShop"
MOD_FILES = ("manifest.json", "mod_main.gd", "shop_item.gd", "client.gd", "state.gd",
             "isolation.gd", "profile_manager.gd", "platform.gd", "achievement.gd",
             "unlocks.gd", "unlock_condition.gd", "plasmid.gd", "unlock_plasmid.gd",
             "run_save_manager.gd", "player_selection_menu.gd", "bodypart_button.gd", "utils.gd",
             "plasmid_manager.gd", "organelles.gd", "catalog.json", "organelles.json")
APWORLD = "pathogenic"
APWORLD_FILES = ("__init__.py", "archipelago.json", "catalog.json", "organelles.json",
                 "docs/en_Pathogenic.md", "docs/setup_en.md")


def archive(output: Path, entries: list[tuple[Path, str]]) -> str:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as pack:
        for source, destination in sorted(entries, key=lambda entry: entry[1]):
            info = zipfile.ZipInfo(destination, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            pack.writestr(info, source.read_bytes())
    temporary.replace(output)
    return hashlib.sha256(output.read_bytes()).hexdigest()


def manifest(root: Path = ROOT) -> dict:
    data = json.loads((root / MOD_ID / "manifest.json").read_text())
    if data["namespace"] + "-" + data["name"] != MOD_ID:
        raise ValueError("Manifest ID does not match the archive directory")
    return data


def check_version(tag: str, root: Path = ROOT) -> str:
    """Fail unless a release tag (v1.2.3) matches the mod and APWorld versions."""
    version = manifest(root)["version_number"]
    world = json.loads((root / "apworld" / APWORLD / "archipelago.json").read_text())
    if tag.removeprefix("v") != version or world["world_version"] != version:
        raise ValueError(
            f"Tag {tag} must equal manifest version_number ({version}) "
            f"and APWorld world_version ({world['world_version']})"
        )
    return version


def stage_workshop(mod_zip: Path, workshop: Path) -> None:
    """Workshop content is exactly one mod ZIP; Mod Loader loads <item id>/*.zip."""
    if workshop.exists():
        shutil.rmtree(workshop)
    workshop.mkdir(parents=True)
    shutil.copy2(mod_zip, workshop / mod_zip.name)


def build(root: Path = ROOT) -> dict:
    manifest(root)
    source = root / MOD_ID
    dist = root / "dist"
    mod_zip = dist / f"{MOD_ID}.zip"
    world = root / "apworld" / APWORLD
    hashes = {
        mod_zip.name: archive(
            mod_zip, [(world / name if name.endswith(".json") and name != "manifest.json" else source / name,
                       f"mods-unpacked/{MOD_ID}/{name}") for name in MOD_FILES]
        ),
        f"{APWORLD}.apworld": archive(
            dist / f"{APWORLD}.apworld",
            [(world / name, f"{APWORLD}/{name}") for name in APWORLD_FILES],
        ),
    }
    stage_workshop(mod_zip, dist / "workshop")
    (dist / "SHA256SUMS").write_text(
        "".join(f"{digest}  {name}\n" for name, digest in hashes.items())
    )
    return hashes


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-tag", help="Only verify that a release tag matches the versions")
    args = parser.parse_args()
    if args.check_tag:
        print(f"Release version: {check_version(args.check_tag)}")
    else:
        for name, digest in build().items():
            print(f"{name}: {digest}")
