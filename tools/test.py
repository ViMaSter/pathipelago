#!/usr/bin/env python3
"""Run real Godot client/state tests against original, minimal game API doubles."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def godot_data_root() -> Path:
    """Godot resolves custom user directories relative to the OS data directory."""
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support"
    if sys.platform == "win32":
        return Path(os.environ["APPDATA"])
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")


def engine_tests(godot: str, live_server: str | None = None, unlocks: bool = False) -> None:
    data_root = godot_data_root()
    data_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pathogenic-multiworld-test-") as temporary, \
            tempfile.TemporaryDirectory(prefix="pathogenic-multiworld-test-", dir=data_root) as user:
        project = Path(temporary)
        shutil.copytree(ROOT / "ViMaSter-MultiworldGGShop",
                        project / "mods-unpacked/ViMaSter-MultiworldGGShop")
        shutil.copytree(ROOT / "tests", project / "tests")
        catalogue = ROOT / "apworld/pathogenic/catalog.json"
        if catalogue.is_file():
            shutil.copy2(catalogue, project / "mods-unpacked/ViMaSter-MultiworldGGShop/catalog.json")
        shop = project / "scn/environ/pickups"
        shop.mkdir(parents=True)
        shutil.copy(ROOT / "tests/stubs/profile_manager.gd", project / "scn/profile_manager.gd")
        config = project / "addons/maaacks_input_remapping/base/scripts/player_config.gd"
        config.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "tests/stubs/player_config.gd", config)
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
        autoload = ""
        if unlocks:
            for source, target in {
                "save_manager.gd": "scn/save_manager.gd",
                "run_save.gd": "scn/run_save_manager.gd",
                "unlock_condition.gd": "scn/metaprogression/unlocks/unlock_condition.gd",
                "plasmid.gd": "scn/metaprogression/plasmids/plasmid.gd",
                "unlock_plasmid.gd": "scn/metaprogression/plasmids/unlock_plasmid.gd",
                "plasmid_manager.gd": "scn/metaprogression/plasmids/plasmid_manager.gd",
            }.items():
                destination = project / target
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / "tests/stubs" / source, destination)
            autoload = ('[autoload]\nG="*res://tests/stubs/globals.gd"\n'
                        'SignalBus="*res://tests/stubs/signal_bus.gd"\n'
                        'SaveManager="*res://scn/save_manager.gd"\n'
                        'RunSaveManager="*res://scn/run_save_manager.gd"\n')
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Pathogenic MultiworldGG isolated tests"\n'
            'config/use_custom_user_dir=true\n'
            f'config/custom_user_dir_name="{Path(user).name}"\n'
            + autoload +
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        )
        command = [
            godot, "--headless", "--path", str(project), "--script",
             ("tests/live_unlocks.gd" if unlocks else "tests/live.gd") if live_server
             else "tests/unlocks.gd" if unlocks else "tests/run.gd",
             "--", user, *([live_server] if live_server else [])]
        try:
            result = subprocess.run(
                command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90,
                env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"},
            )
        except subprocess.TimeoutExpired as error:
            print((error.stdout or b"").decode(errors="replace"))
            raise RuntimeError("Godot integration tests timed out") from error
        print(result.stdout)
        if result.returncode or "SCRIPT ERROR:" in result.stdout or "TEST FAILED:" in result.stdout \
                or "failures=0" not in result.stdout:
            raise RuntimeError("Godot integration tests failed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--live-server", help="Fresh three-slot seed: Pathogenic1/2 enabled, Pathogenic3 DeathLink off; shipment 2 crosses to slot 2")
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern="test_*.py")
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        raise SystemExit(1)
    engine_tests(args.godot, args.live_server)
    if not args.live_server:
        engine_tests(args.godot, unlocks=True)
