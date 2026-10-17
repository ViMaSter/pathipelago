#!/usr/bin/env python3
"""Export the sprites that shop pedestals display as shop-sprites/[ITEMNAME].png.

Uses GDRE Tools to recover the installed demo's resources and textures into a
temporary directory. The output contains game assets: keep it local, never commit
or distribute it.
"""

import argparse
import csv
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GAME = Path("~/Library/Application Support/Steam/steamapps/common/"
                    "Pathogenic Demo/Pathogenic.app")
DEFAULT_GDRE = Path("/Applications/Godot RE Tools.app/Contents/MacOS/Godot RE Tools")


def field(text: str, name: str) -> str:
    match = re.search(rf'^{name} = "(.*)"$', text, re.MULTILINE)
    return match.group(1) if match else ""


def number(text: str, name: str) -> float:
    match = re.search(rf"^{name} = ([0-9.eE+-]+)$", text, re.MULTILINE)
    return float(match.group(1)) if match else 0.0


def translations(path: Path) -> dict:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return {row["key"]: row["en"] for row in csv.DictReader(handle) if row.get("key")}


def display_name(names: dict, key: str) -> str:
    name = re.sub(r"\[/?[^\]]*\]", "", names.get(key, key)).strip()
    return re.sub(r'[/:\\"*?<>|]', "-", name) or key


def recover(gdre: Path, pack: Path, output: Path) -> None:
    command = [str(gdre), "--headless", f"--recover={pack}", f"--output={output}",
               "--include=res://.godot/exported/**/*.res",
               "--include=res://.godot/imported/*.ctex",
               "--include=res://translations/translations.en.translation"]
    result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    if result.returncode != 0 or not (output / "translations/translations.csv").is_file():
        raise SystemExit(f"GDRE recovery failed ({result.returncode}); see {output / 'gdre_export.log'}")


def uid_paths(project: Path) -> dict:
    paths = {}
    for meta in project.rglob("*.import"):
        match = re.search(r'^uid="(uid://[^"]+)"$', meta.read_text(encoding="utf-8", errors="replace"), re.MULTILINE)
        if match:
            paths[match.group(1)] = "res://" + meta.relative_to(project).as_posix().removesuffix(".import")
    return paths


def collect(project: Path) -> list:
    names = translations(project / "translations/translations.csv")
    uids = uid_paths(project)
    entries = []
    for resource in sorted((project / "scn/player/bodyparts").rglob("*.tres")):
        text = resource.read_text(encoding="utf-8")
        icon = field(text, "icon_texture")
        if not icon:
            continue
        entries.append({
            "name": display_name(names, field(text, "ui_name")), "id": resource.stem,
            "kind": resource.parent.relative_to(project / "scn/player/bodyparts").as_posix(),
            "texture": icon, "background": field(text, "background_texture"),
            "disabled": "disabled = true" in text})
    for resource in sorted((project / "scn/player/mutations").rglob("*.tres")):
        text = resource.read_text(encoding="utf-8")
        texture = field(text, "texture")
        texture = uids.get(texture, texture)
        if texture and number(text, "reward_drop_rate") > 0:
            entries.append({
                "name": display_name(names, field(text, "ui_name")), "id": resource.stem,
                "kind": "mutation", "texture": texture, "background": "",
                "disabled": "disabled = true" in text})
    return entries


def export(project: Path, output: Path) -> int:
    entries = collect(project)
    counts: dict = {}
    for entry in entries:
        counts[entry["name"]] = counts.get(entry["name"], 0) + 1
    if output.exists():
        shutil.rmtree(output)
    (output / "backgrounds").mkdir(parents=True)
    rows = []
    for entry in entries:
        source = project / entry["texture"].removeprefix("res://")
        if not source.is_file():
            print(f"missing texture for {entry['id']}: {entry['texture']}", file=sys.stderr)
            continue
        stem = entry["name"] if counts[entry["name"]] == 1 else f"{entry['name']} ({entry['id']})"
        shutil.copyfile(source, output / f"{stem}.png")
        background = project / entry["background"].removeprefix("res://") if entry["background"] else None
        if background is not None and background.is_file():
            shutil.copyfile(background, output / "backgrounds" / f"{stem}.png")
        rows.append([f"{stem}.png", entry["id"], entry["kind"], entry["texture"], entry["background"],
                     "yes" if entry["disabled"] else "no"])
    with (output / "index.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["file", "resource_id", "kind", "texture", "background", "disabled"])
        writer.writerows(rows)
    return len(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME)
    parser.add_argument("--gdre", type=Path, default=DEFAULT_GDRE)
    parser.add_argument("--output", type=Path, default=ROOT / "shop-sprites")
    args = parser.parse_args()
    pack = args.game / "Contents/Resources/Pathogenic.pck"
    if not pack.is_file() or not args.gdre.is_file():
        raise SystemExit(f"Need {pack} and GDRE at {args.gdre}")
    with tempfile.TemporaryDirectory(prefix="pathogenic-sprites-") as temporary:
        project = Path(temporary) / "project"
        recover(args.gdre, pack, project)
        count = export(project, args.output.resolve())
    print(f"Exported {count} shop sprites to {args.output.resolve()}")


if __name__ == "__main__":
    main()
