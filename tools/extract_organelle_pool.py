#!/usr/bin/env python3
"""Extract the organelle random-drop pool from a private, recovered Godot resource tree.

The pool is every enabled external/internal bodypart listed in the game's bodypart
registry. No character filters organelle drops, so one pool serves every character.
Existing IDs are retained by key; removals are retired instead of recycled.
"""

import argparse
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_unlock_catalog import Extractor  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "apworld/pathogenic/organelles.json"
POOL_SCHEMA = 1
REGISTRY = "res://scn/player/bodyparts/all_bodyparts.tres"
PREFIXES = ("res://scn/player/bodyparts/external/", "res://scn/player/bodyparts/internal/")


def final_resource(text):
    """Bodypart files may embed [resource]-like subresources; only the last section counts."""
    section = text[text.rfind("\n[resource]"):]
    return dict(re.findall(r"^(\w+) = (.*)$", section, re.M))


def pool_entries(recovered):
    extractor = Extractor(recovered)
    root = Path(recovered)
    registry = (root / REGISTRY.removeprefix("res://")).read_text(encoding="utf-8")
    entries = []
    for path in re.findall(r'"(res://scn/player/bodyparts/[^"]+\.tres)"', registry):
        if not path.startswith(PREFIXES):
            continue
        props = final_resource((root / path.removeprefix("res://")).read_text(encoding="utf-8"))
        if props.get("disabled") == "true":
            continue
        entries.append({
            "key": path.removeprefix("res://scn/player/bodyparts/").removesuffix(".tres"),
            "resource": path,
            "name": extractor.label(props["ui_name"]),
        })
    return entries


def build_pool(recovered, previous=None):
    found = pool_entries(recovered)
    old = {entry["key"]: entry for entry in (previous or {}).get("entries", [])}
    retired = dict((previous or {}).get("retired", {}))
    keys = {entry["key"] for entry in found}
    for key, entry in old.items():
        if key not in keys:
            retired[key] = entry["id"]
    next_id = max([0, *(e["id"] for e in old.values()), *retired.values()]) + 1
    entries = []
    for entry in sorted(found, key=lambda e: e["key"]):
        if entry["key"] in old:
            entry["id"] = old[entry["key"]]["id"]
        elif entry["key"] in retired:
            entry["id"] = retired.pop(entry["key"])
        else:
            entry["id"] = next_id
            next_id += 1
        entries.append(entry)
    names = [entry["name"] for entry in entries]
    if len(set(names)) != len(names):
        raise ValueError("Organelle names are not unique")
    return {"schema": POOL_SCHEMA, "entries": sorted(entries, key=lambda e: e["id"]),
            "retired": dict(sorted(retired.items()))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recovered", type=Path, required=True,
                        help="Private recovered resource root (never copied)")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="Verify without rewriting")
    args = parser.parse_args()
    previous = json.loads(args.output.read_text()) if args.output.exists() else None
    rendered = json.dumps(build_pool(args.recovered, previous), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not args.output.exists() or args.output.read_text() != rendered:
            raise SystemExit("Organelle pool is out of date")
    else:
        args.output.write_text(rendered, encoding="utf-8")
    print(f"{len(json.loads(rendered)['entries'])} organelles")


if __name__ == "__main__":
    main()
