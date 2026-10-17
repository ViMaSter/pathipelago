#!/usr/bin/env python3
"""Validate the built APWorld and Godot client against a real MultiworldGG runtime."""

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest  # Enables MultiworldGG's AP_TEST_WORLDS filter.
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.build import build
from tools.test import engine_tests


def main(runtime: Path, godot: str) -> None:
    runtime = runtime.resolve(strict=True)
    if not (runtime / "Generate.py").is_file():
        raise ValueError(f"Not a MultiworldGG source runtime: {runtime}")
    build()
    custom = runtime / "custom_worlds"
    custom.mkdir(exist_ok=True)
    world_archive = custom / "pathogenic.apworld"
    if world_archive.exists():
        raise ValueError(f"Use a clean validation runtime without an existing {world_archive}")
    shutil.copy2(ROOT / "dist/pathogenic.apworld", world_archive)
    try:
        os.environ["SKIP_REQUIREMENTS_UPDATE"] = "1"
        os.environ["AP_TEST_WORLDS"] = "pathogenic"
        sys.path.insert(0, str(runtime))
        os.chdir(runtime)
        import Generate
        import Main
        import Utils
        from Options import OptionError
        from worlds import AutoWorldRegister, ensure_worlds_loaded

        ensure_worlds_loaded()
        world_type = AutoWorldRegister.world_types["Pathogenic"]
        if world_type.item_name_to_id != {"Research Grant": 402939001}:
            raise AssertionError("Pathogenic item IDs changed")
        print(f"MULTIWORLDGG_TEST release={Utils.__version__}", flush=True)
        with tempfile.TemporaryDirectory(prefix="pathogenic-mwgg-live-") as temporary:
            directory = Path(temporary)
            players = directory / "players"
            players.mkdir()
            output = directory / "output"
            output.mkdir()

            def generate(count: int, flags: dict, two_players: bool = False):
                for path in players.glob("*.yaml"):
                    path.unlink()
                for player in range(1, 3 if two_players else 2):
                    options = {"shop_checks": count, **flags}
                    if two_players and player == 2:
                        options["plando_items"] = [{
                            "item": "Research Grant", "location": "Shop Shipment 002",
                            "world": "Pathogenic1", "from_pool": True, "force": True,
                        }]
                    (players / f"{player}.yaml").write_text(json.dumps({
                        "name": f"Pathogenic{player}", "game": "Pathogenic", "Pathogenic": options,
                    }))
                args = Generate.mystery_argparse([
                    "--player_files_path", str(players), "--outputpath", str(output),
                    "--seed", "7", "--spoiler", "0", "--plando", "items",
                ])
                settings, seed = Generate.main(args)
                return Main.main(settings, seed)

            source_names = {
                "shops": "shop_unlocks", "item_rooms": "item_room_unlocks",
                "boss_rewards": "boss_reward_unlocks", "level_ups": "level_up_unlocks",
            }
            for selected in source_names:
                flags = {option: source == selected for source, option in source_names.items()}
                multiworld = generate(1, flags)
                world = multiworld.worlds[1]
                expected = {"schema": 2, "shop_checks": 1,
                            "sources": {source: source == selected for source in source_names}}
                if world.fill_slot_data() != expected or len(multiworld.get_locations(1)) != 1:
                    raise AssertionError(f"Incorrect single-source slot data: {selected}")
            multiworld = generate(10000, {})
            if len(multiworld.get_locations(1)) != 10000:
                raise AssertionError("10,000-check boundary was not generated")
            try:
                generate(1, {option: False for option in source_names.values()})
            except OptionError as error:
                if "enable at least one" not in str(error):
                    raise
            else:
                raise AssertionError("All-disabled sources were accepted")
            multiworld = generate(2, {}, two_players=True)
            location = multiworld.get_location("Shop Shipment 002", 1)
            if location.item.player != 2:
                raise AssertionError("Cross-player fixture was not placed as requested")
            archive = output / f"AP_{multiworld.seed_name}.zip"
            live_test(runtime, godot, archive, directory)
            print("MULTIWORLDGG_TEST generation_boundaries=true sources=true live=true", flush=True)
    finally:
        world_archive.unlink()


def live_test(runtime: Path, godot: str, archive: Path, directory: Path) -> None:
    from websockets.sync.client import connect

    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    endpoint = f"ws://127.0.0.1:{port}"
    with (directory / "server.log").open("w+") as log:
        server = subprocess.Popen(
            [sys.executable, str(runtime / "MultiServer.py"), str(archive),
             "--host", "127.0.0.1", "--port", str(port)],
            cwd=runtime, stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT,
        )
        try:
            deadline = time.monotonic() + 30
            while True:
                if server.poll() is not None:
                    raise RuntimeError("MultiworldGG test server exited before becoming ready")
                try:
                    with connect(endpoint, open_timeout=1) as websocket:
                        packets = json.loads(websocket.recv(timeout=2))
                        if not any(packet.get("cmd") == "RoomInfo" for packet in packets):
                            raise RuntimeError("Test server did not send RoomInfo")
                    break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise TimeoutError("MultiworldGG test server did not become ready")
                    time.sleep(0.1)
            engine_tests(godot, endpoint)
            server.communicate("/exit\n".encode(), timeout=15)
            if server.returncode:
                raise RuntimeError(f"MultiworldGG test server exited with {server.returncode}")
            from Utils import restricted_loads
            saved = restricted_loads(zlib.decompress(archive.with_suffix(".apsave").read_bytes()))
            if saved["client_game_state"].get((0, 1)) != 30:
                raise AssertionError("Server did not persist the sender's completed goal")
            if not {402938001, 402938002}.issubset(saved["location_checks"].get((0, 1), set())):
                raise AssertionError("Server did not persist both confirmed checks")
            print("MULTIWORLDGG_TEST server_goal_and_checks_persisted=true", flush=True)
        finally:
            if server.poll() is None:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()
            log.seek(0)
            print(log.read())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    main(args.runtime, args.godot)
