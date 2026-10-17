#!/usr/bin/env python3
"""Build reproducible archives containing only this project's original source."""

import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MOD_ID = "Local-ArchipelagoShop"


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


def build() -> dict:
    source = ROOT / "mods-unpacked" / MOD_ID
    manifest = json.loads((source / "manifest.json").read_text())
    if manifest["namespace"] + "-" + manifest["name"] != MOD_ID:
        raise ValueError("Manifest ID does not match the archive directory")
    mod_files = [
        (source / name, f"mods-unpacked/{MOD_ID}/{name}")
        for name in ("manifest.json", "mod_main.gd", "shop_item.gd", "client.gd", "state.gd")
    ]
    world = ROOT / "apworld" / "pathogenic_demo"
    hashes = {
        f"{MOD_ID}.zip": archive(ROOT / "dist" / f"{MOD_ID}.zip", mod_files),
        "pathogenic_demo.apworld": archive(
            ROOT / "dist" / "pathogenic_demo.apworld",
            [(world / name, f"pathogenic_demo/{name}")
             for name in ("__init__.py", "archipelago.json",
                          "docs/en_Pathogenic Demo.md", "docs/setup_en.md")],
        ),
    }
    (ROOT / "dist" / "SHA256SUMS").write_text(
        "".join(f"{digest}  {name}\n" for name, digest in hashes.items())
    )
    return hashes


if __name__ == "__main__":
    for name, digest in build().items():
        print(f"{name}: {digest}")
