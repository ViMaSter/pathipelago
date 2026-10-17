#!/usr/bin/env python3
"""Write a SteamCMD workshop_build_item VDF for the Pathogenic Workshop item.

Only needed once, to create the item (no --item-id). CI updates it afterwards.
  python3 tools/build.py
  python3 tools/workshop_vdf.py --preview /abs/preview.png > /tmp/item.vdf
  steamcmd +login <user> +workshop_build_item /tmp/item.vdf +quit
SteamCMD prints the new PublishedFileId; store it as STEAM_WORKSHOP_ITEM_ID.
"""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_ID = "3808690"
TITLE = "MultiworldGG Multiworld (Remote Unlocks)"
DESCRIPTION = (
    "Connects Pathogenic to an [url=https://multiworld.gg]MultiworldGG[/url] multiworld.\n\n"
    "One pedestal in shops, blue item rooms, boss rewards and level-up drafts becomes a "
    "Remote Unlock that sends a check to another player's game. Received Research Grants "
    "pay out coins.\n\n"
    "Off by default: enable and connect in Settings > MultiworldGG.\n"
    "APWorld, setup guide and source: [url=https://github.com/ViMaSter/pathipelago]"
    "github.com/ViMaSter/pathipelago[/url]"
)
VISIBILITY = {"public": 0, "friends": 1, "private": 2, "unlisted": 3}


def quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def vdf(content: Path, item_id: str, preview: Path | None, visibility: str, note: str) -> str:
    fields = {
        "appid": APP_ID,
        "publishedfileid": item_id,
        "contentfolder": str(content.resolve(strict=True)),
        "visibility": str(VISIBILITY[visibility]),
        "title": TITLE,
        "description": DESCRIPTION,
        "changenote": note,
    }
    if preview:
        fields["previewfile"] = str(preview.resolve(strict=True))
    body = "".join(f"\t{quote(key)}\t{quote(value)}\n" for key, value in fields.items())
    return '"workshopitem"\n{\n' + body + "}\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--item-id", default="0", help="0 creates a new item")
    parser.add_argument("--content", type=Path, default=ROOT / "dist/workshop")
    parser.add_argument("--preview", type=Path, help="Original artwork, PNG/JPG/GIF under 1 MB")
    parser.add_argument("--visibility", choices=VISIBILITY, default="private")
    parser.add_argument("--note", default="Initial upload")
    args = parser.parse_args()
    print(vdf(args.content, args.item_id, args.preview, args.visibility, args.note), end="")
