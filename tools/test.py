#!/usr/bin/env python3
"""Run real Godot client/state tests against original, minimal game API doubles."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def engine_tests(godot: str, live_server: str | None = None) -> None:
    # Godot resolves custom user directories relative to the OS data directory.
    data_root = Path.home() / "Library/Application Support"
    with tempfile.TemporaryDirectory(prefix="pathogenic-ap-test-") as temporary, \
            tempfile.TemporaryDirectory(prefix="pathogenic-ap-test-", dir=data_root) as user:
        project = Path(temporary)
        shutil.copytree(ROOT / "mods-unpacked", project / "mods-unpacked")
        shutil.copytree(ROOT / "tests", project / "tests")
        shop = project / "scn/environ/pickups"
        shop.mkdir(parents=True)
        shutil.copy(ROOT / "tests/stubs/shop_item.gd", shop / "shop_item.gd")
        shutil.copy(ROOT / "tests/stubs/bodypart_reward.gd", shop / "bodypart_reward.gd")
        room = project / "scn/environ/rooms/special"
        room.mkdir(parents=True)
        shutil.copy(ROOT / "tests/stubs/shop.gd", room / "shop.gd")
        shutil.copy(ROOT / "tests/stubs/item_room.gd", room / "item_room.gd")
        ui = project / "scn/ui"
        ui.mkdir(parents=True)
        shutil.copy(ROOT / "tests/stubs/options_menu.gd", ui / "options_menu.gd")
        (ui / "start_menus").mkdir()
        shutil.copy(ROOT / "tests/stubs/player_selection_menu.gd", ui / "start_menus/player_selection_menu.gd")
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Pathogenic AP isolated tests"\n'
            'config/use_custom_user_dir=true\n'
            f'config/custom_user_dir_name="{Path(user).name}"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        )
        result = subprocess.run(
            [godot, "--headless", "--path", str(project), "--script",
             "tests/live.gd" if live_server else "tests/run.gd",
             "--", user, *([live_server] if live_server else [])],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90,
            env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"},
        )
        print(result.stdout)
        if result.returncode or "SCRIPT ERROR:" in result.stdout or "TEST FAILED:" in result.stdout \
                or "failures=0" not in result.stdout:
            raise RuntimeError("Godot integration tests failed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--live-server", help="Fresh two-slot test seed: Pathogenic1/Pathogenic2; shipment 2 crosses to slot 2")
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern="test_*.py")
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        raise SystemExit(1)
    engine_tests(args.godot, args.live_server)
