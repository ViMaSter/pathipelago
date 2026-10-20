#!/usr/bin/env python3
"""Extract factual unlock identities from a private, recovered Godot resource tree.

No game scripts are executed or distributed. Existing IDs are retained by key;
removals fail closed so an update cannot silently invalidate released seeds.
"""

import argparse
from collections import Counter
import csv
import json
from pathlib import Path
import posixpath
import re


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "apworld/pathogenic/catalog.json"
CATALOG_SCHEMA = 1
# Previously catalogued standalone scenes are absent from every live map.
# Reserve their published IDs permanently rather than recycling network IDs.
RETIRED_IDS = {"plasmid:global:strafer": 309, "plasmid:global:worm": 310}
# v1.2.1 ParasiteType and the corresponding full-game resource suffixes.
PARASITES = {
    "bacteria": (0, "player_green_name"),
    "strafer": (1, "player_strafer_name"),
    "worm": (2, "player_worm_name"),
    "coop": (3, "player_coop_name"),
    "nanobot": (4, "player_nanobot_name"),
    "amoeba": (5, "player_amoeba_name"),
    "diatom": (3, "player_coop_name"),
    "collector": (7, "player_collector_name"),
}
KINDS = {"character", "plasmid", "loadout", "organelle", "environment"}
ATTR = re.compile(r'(\w+)="([^"]*)"')
REFERENCE = re.compile(r'^(ExtResource|SubResource)\("([^"]+)"\)$')


class Document:
    def __init__(self, root, path):
        self.root = root
        self.path = path
        local = root / path.removeprefix("res://")
        self.text = local.read_text(encoding="utf-8")
        self.sections = []
        current = None
        for line in self.text.splitlines():
            if line.startswith("["):
                if not line.endswith("]"):
                    raise ValueError(f"Unresolved section in {path}: {line}")
                kind = line[1:].split(" ", 1)[0].rstrip("]")
                current = (kind, dict(ATTR.findall(line)), {})
                # Instance is a resource reference, not a quoted attribute.
                instance = re.search(r'instance=(ExtResource\("[^"]+"\))', line)
                if instance:
                    current[1]["instance"] = instance[1]
                self.sections.append(current)
            elif current is not None and " = " in line:
                key, value = line.split(" = ", 1)
                current[2][key] = value

    def resource(self):
        return next(props for kind, _, props in self.sections if kind == "resource")

    def reference(self, value):
        match = REFERENCE.fullmatch(value)
        if not match:
            raise ValueError(f"Unresolved resource reference {self.path}: {value}")
        kind, identity = match.groups()
        if kind == "ExtResource":
            attrs = next((a for k, a, _ in self.sections
                          if k == "ext_resource" and a["id"] == identity), None)
            if attrs is None:
                raise ValueError(f"Missing external resource {self.path}: {identity}")
            return attrs["path"]
        if not any(k == "sub_resource" and a["id"] == identity
                   for k, a, _ in self.sections):
            raise ValueError(f"Missing subresource {self.path}: {identity}")
        return f"{self.path}::{identity}"

    def reference_list(self, value):
        if not value.startswith("[") or not value.endswith("]"):
            raise ValueError(f"Unresolved resource list {self.path}: {value}")
        return [self.reference(part.strip()) for part in value[1:-1].split(",")
                if part.strip()]


class Extractor:
    def __init__(self, recovered):
        self.root = Path(recovered)
        self.documents = {}
        with (self.root / "translations/translations.csv").open(
                encoding="utf-8-sig", newline="") as stream:
            self.translations = {row["key"]: row["en"] for row in csv.DictReader(stream)}

    def document(self, path):
        path = path.split("::", 1)[0]
        if path not in self.documents:
            self.documents[path] = Document(self.root, path)
        return self.documents[path]

    def resource(self, identity):
        doc = self.document(identity)
        if "::" in identity:
            sub = identity.split("::", 1)[1]
            props = next(p for k, a, p in doc.sections
                         if k == "sub_resource" and a["id"] == sub)
        else:
            props = doc.resource()
        return doc, props

    def label(self, raw):
        key = json.loads(raw)
        if key not in self.translations and key != "???":
            raise ValueError(f"Unresolved English translation: {key!r}")
        text = self.translations.get(key, key)
        if not text:
            raise ValueError(f"Empty English translation: {key}")
        return " ".join(re.sub(r"\[[^]]+\]", "", text).split())

    def character(self, suffix):
        parasite, key = PARASITES[suffix]
        return parasite, self.label(json.dumps(key))

    def gate(self, doc, value):
        identity = doc.reference(value)
        gate_doc, props = self.resource(identity)
        stat = gate_doc.reference(props["stat"])
        _, stat_props = self.resource(stat)
        aggregation = int(stat_props.get("aggregation", "1"))
        if aggregation not in (1, 2, 3, 4):
            raise ValueError(f"Unresolved stat aggregation: {stat}")
        return {
            "condition": identity,
            "stat": stat,
            "threshold": float(props.get("threshold", "0")),
            "comparison": {1: ">=", 2: "<=", 3: ">=", 4: "truthy"}[aggregation],
            "global": props.get("global", "false") == "true",
            "requires_full_game": props.get("requires_full_game", "false") == "true",
        }

    def scene(self, path, ancestors=()):
        if path in ancestors:
            raise ValueError(f"Scene inheritance cycle: {path}")
        doc = self.document(path)
        attrs, props = next((a, p) for k, a, p in doc.sections if k == "node")
        inherited = {}
        if "instance" in attrs:
            inherited = self.scene(doc.reference(attrs["instance"]), ancestors + (path,))
        inherited.update({k: (doc, v) for k, v in props.items()})
        return inherited

    def validate_map_connections(self, doc):
        nodes = {attrs["name"]: doc.reference(attrs["instance"])
                 for kind, attrs, _ in doc.sections
                 if kind == "node" and attrs.get("parent") == "."
                 and "instance" in attrs
                 and not doc.reference(attrs["instance"]).endswith("/background.tscn")}
        starts = {name for name, scene in nodes.items()
                  if scene.endswith("/starting_plasmid.tscn")}
        if len(starts) != 1:
            raise ValueError(f"Expected one starting plasmid: {doc.path}")
        edges = {name: set() for name in nodes}
        for kind, attrs, props in doc.sections:
            if kind != "node" or "from" not in props or "to" not in props:
                continue
            endpoints = []
            for field in ("from", "to"):
                match = re.fullmatch(r'NodePath\("([^"]+)"\)', props[field])
                if not match:
                    raise ValueError(f"Unresolved map connection: {doc.path}: {props[field]}")
                endpoints.append(posixpath.normpath(posixpath.join(
                    attrs["parent"], attrs["name"], match[1])))
            left, right = endpoints
            if left not in edges or right not in edges:
                raise ValueError(f"Missing map connection target: {doc.path}: {endpoints}")
            edges[left].add(right)
            edges[right].add(left)
        depths = dict.fromkeys(starts, 0)
        pending = sorted(starts)
        while pending:
            current = pending.pop(0)
            for neighbor in sorted(edges[current] - depths.keys()):
                depths[neighbor] = depths[current] + 1
                pending.append(neighbor)
        unreachable = nodes.keys() - depths.keys()
        if unreachable:
            raise ValueError(f"Unreachable plasmid nodes: {doc.path}: {sorted(unreachable)}")
        return depths

    def extract(self):
        entries = []
        base = "res://scn/metaprogression/"
        chars = base + "unlocks/parasite_unlocks/parasite_unlocks.tres"
        doc, props = self.resource(chars)
        for identity in doc.reference_list(props["parasite_unlock_list"]):
            child_doc, child = self.resource(identity)
            entries.append({
                "key": "character:" + identity, "kind": "character",
                "name": "Character: " + self.label(child["ui_name"]),
                "parasite": int(child.get("parasite_type", "0")),
                "resource": identity, **self.gate(child_doc, child["unlock"]),
            })
        env_path = base + "unlocks/environmental_unlocks/env_unlocks.tres"
        doc, props = self.resource(env_path)
        for identity in doc.reference_list(props["env_unlock_list"]):
            child_doc, child = self.resource(identity)
            entries.append({
                "key": "environment:" + identity, "kind": "environment",
                "name": "Environment: " + self.label(child["ui_name"]),
                "parasite": -1, "resource": identity,
                "environment": json.loads(child["name"]),
                **self.gate(child_doc, child["unlock"]),
            })
        maps = sorted(self.root.glob("scn/metaprogression/plasmids/plasmid_map*.tscn"))
        if len(maps) != 7:
            raise ValueError(f"Expected seven full-game plasmid maps, found {len(maps)}")
        for path in maps:
            suffix = path.stem.removeprefix("plasmid_map").lstrip("_") or "bacteria"
            parasite, character = self.character(suffix)
            identity = "res://" + path.relative_to(self.root).as_posix()
            doc = self.document(identity)
            depths = self.validate_map_connections(doc)
            plasmids = []
            for kind, attrs, props in doc.sections:
                if kind != "node" or attrs.get("parent") != "." or "instance" not in attrs:
                    continue
                scene_path = doc.reference(attrs["instance"])
                if scene_path.endswith("/starting_plasmid.tscn"):
                    continue
                effective = self.scene(scene_path)
                effective.update({k: (doc, v) for k, v in props.items()})
                if "mutation_res" in effective:
                    mutation_doc, mutation_ref = effective["mutation_res"]
                    _, mutation = self.resource(mutation_doc.reference(mutation_ref))
                    label = self.label(mutation["ui_name"])
                else:
                    label = self.label(effective["ui_name"][1])
                node = attrs["name"]
                entry = {
                    "key": f"plasmid:{parasite}:{node}", "kind": "plasmid",
                    "name": f"{character} Plasmid: {label} [{node}]",
                    "parasite": parasite, "condition": "", "map": identity, "node": node,
                    "scene": scene_path, "section": f"plasmids{parasite}", "save_key": node,
                }
                if "unlock_name" in effective:
                    entry.update(section="unlocks", save_key=json.loads(effective["unlock_name"][1]))
                plasmids.append(entry)
            # Shared slot N: every character's Nth plasmid by distance from the start node.
            plasmids.sort(key=lambda entry: (depths[entry["node"]], entry["node"]))
            for slot, entry in enumerate(plasmids, 1):
                entry["slot"] = slot
            entries.extend(plasmids)
        loadouts = sorted(self.root.glob("scn/metaprogression/loadouts/loadout_*.tres"))
        full_loadouts = [p for p in loadouts if not p.stem.endswith("_demo")]
        if len(full_loadouts) != 7:
            raise ValueError(f"Expected seven full-game loadouts, found {len(full_loadouts)}")
        for path in full_loadouts:
            parasite, character = self.character(path.stem.removeprefix("loadout_"))
            identity = "res://" + path.relative_to(self.root).as_posix()
            doc = self.document(identity)
            options = []
            for category in doc.reference_list(doc.resource()["categories"]):
                category_doc, category_props = self.resource(category)
                options.extend(category_doc.reference_list(category_props["options"]))
            for option in options:
                option_doc, props = self.resource(option)
                if props.get("unlock", "null") == "null":
                    continue
                bodypart = option_doc.reference(props["bodypart"])
                _, body = self.resource(bodypart)
                entries.append({
                    "key": "loadout:" + option, "kind": "loadout",
                    "name": f"{character} Loadout: {self.label(body['ui_name'])}",
                    "parasite": parasite, "resource": option, "bodypart": bodypart,
                    **self.gate(option_doc, props["unlock"]),
                })
        for path in sorted(self.root.glob("scn/player/bodyparts/**/*.tres")):
            identity = "res://" + path.relative_to(self.root).as_posix()
            doc = self.document(identity)
            props = doc.resource()
            if props.get("unlock", "null") == "null":
                continue
            entries.append({
                "key": "organelle:" + identity, "kind": "organelle",
                "name": "Organelle: " + self.label(props["ui_name"]),
                "parasite": -1, "resource": identity,
                **self.gate(doc, props["unlock"]),
            })
        return entries


def validate_catalog(catalog, require_slots=True):
    if catalog.get("schema") != CATALOG_SCHEMA or not isinstance(catalog.get("entries"), list):
        raise ValueError("Unsupported catalogue schema")
    for field in ("id", "key", "name"):
        values = [entry[field] for entry in catalog["entries"]]
        if len(set(values)) != len(values):
            raise ValueError(f"Duplicate catalogue {field}")
    for entry in catalog["entries"]:
        if (type(entry["id"]) is not int or not 0 <= entry["id"] < 10000
                or entry["kind"] not in KINDS or type(entry["parasite"]) is not int
                or not -1 <= entry["parasite"] <= 7):
            raise ValueError(f"Invalid catalogue entry: {entry}")
        if entry["kind"] == "plasmid":
            if (not all(entry.get(field) for field in ("node", "section", "save_key"))
                    or not isinstance(entry.get("map"), str)
                    or not entry["map"] and RETIRED_IDS.get(entry["key"]) != entry["id"]):
                raise ValueError(f"Missing plasmid identity: {entry['key']}")
            if require_slots and entry["map"] and (type(entry.get("slot")) is not int or entry["slot"] < 1):
                raise ValueError(f"Missing plasmid slot: {entry['key']}")
        elif not entry.get("condition"):
            raise ValueError(f"Missing native gate: {entry['key']}")
    slots = [(entry["parasite"], entry.get("slot")) for entry in catalog["entries"]
             if entry["kind"] == "plasmid" and entry["map"] and require_slots]
    if len(set(slots)) != len(slots):
        raise ValueError("Duplicate plasmid slot")


def build_catalog(recovered, previous=None):
    entries = Extractor(recovered).extract()
    previous = previous or {"schema": CATALOG_SCHEMA, "entries": []}
    # Releases before shared plasmid slots lack the derived slot field.
    validate_catalog(previous, require_slots=False)
    old_ids = {entry["key"]: entry["id"] for entry in previous["entries"]}
    for key, identity in RETIRED_IDS.items():
        if key in old_ids and old_ids[key] != identity:
            raise ValueError(f"Retired catalogue ID changed: {key}")
    removed = old_ids.keys() - {entry["key"] for entry in entries} - RETIRED_IDS.keys()
    if removed:
        raise ValueError(f"Previously released unlocks disappeared: {sorted(removed)}")
    next_id = max(old_ids.values(), default=-1) + 1
    for entry in sorted(entries, key=lambda entry: entry["key"]):
        if entry["key"] in old_ids:
            entry["id"] = old_ids[entry["key"]]
        else:
            while next_id in RETIRED_IDS.values():
                next_id += 1
            entry["id"] = next_id
            next_id += 1
    catalog = {"schema": CATALOG_SCHEMA, "entries": sorted(entries, key=lambda entry: entry["id"])}
    validate_catalog(catalog)
    return catalog


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recovered", type=Path, required=True,
                        help="Private recovered v1.2.1 resource root (never copied)")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="Verify without rewriting")
    args = parser.parse_args()
    previous = json.loads(args.output.read_text()) if args.output.exists() else None
    catalog = build_catalog(args.recovered, previous)
    rendered = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not args.output.exists() or args.output.read_text() != rendered:
            raise SystemExit("Catalogue is out of date")
    else:
        args.output.write_text(rendered, encoding="utf-8")
    print(json.dumps(dict(sorted(Counter(e["kind"] for e in catalog["entries"]).items()))))


if __name__ == "__main__":
    main()
