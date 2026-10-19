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
        import worlds
        from worlds import AutoWorldRegister

        if hasattr(worlds, "ensure_worlds_loaded"):
            worlds.ensure_worlds_loaded()
        world_type = AutoWorldRegister.world_types["Pathogenic"]
        if world_type.item_name_to_id.get("Coins") != 402939001 \
                or len(world_type.item_name_to_id) < 300:
            raise AssertionError("Pathogenic item catalogue is missing")
        print(f"MULTIWORLDGG_TEST release={Utils.__version__}", flush=True)
        with tempfile.TemporaryDirectory(prefix="pathogenic-mwgg-live-") as temporary:
            directory = Path(temporary)
            players = directory / "players"
            players.mkdir()
            output = directory / "output"
            output.mkdir()

            category_options = ["remote_characters", "remote_plasmids", "remote_loadouts",
                                "remote_organelles", "remote_environment"]

            delivery_item = "Coins"

            def generate(count: int, flags: dict, three_players: bool = False, catalogue: bool = False):
                for path in players.glob("*.yaml"):
                    path.unlink()
                for player in range(1, 4 if three_players else 2):
                    options = {"coin_checks": count,
                               **{key: catalogue for key in category_options}, **flags}
                    if three_players and player == 3:
                        options["death_link"] = False
                    if three_players and player == 2:
                        options["plando_items"] = [{
                            "item": delivery_item, "location": "Shop Shipment 002",
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
                expected = {"schema": 4, "catalog_schema": 1, "unlock_ids": [],
                            "checks": 1, "coin_amount": 15, "dna_amount": 1,
                            "plasmid_fragment_amount": 1, "death_link": True,
                            "required_victories": 0,
                            "sources": {source: source == selected for source in source_names}}
                if world.fill_slot_data() != expected or len(multiworld.get_locations(1)) != 1:
                    raise AssertionError(f"Incorrect single-source slot data: {selected}")
            for enabled in (False, True):
                multiworld = generate(1, {"death_link": enabled})
                if multiworld.worlds[1].fill_slot_data()["death_link"] is not enabled:
                    raise AssertionError(f"Incorrect DeathLink slot data: {enabled}")
            for victories in (0, 1, 50):
                multiworld = generate(1, {"required_victories": victories})
                data = multiworld.worlds[1].fill_slot_data()
                if data["required_victories"] != victories or data["checks"] != 1:
                    raise AssertionError(f"Incorrect victory goal slot data: {victories}")
            multiworld = generate(0, {})
            if multiworld.get_locations(1) or multiworld.worlds[1].fill_slot_data()["checks"] != 0:
                raise AssertionError("Zero-check boundary was not generated")
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
            multiworld = generate(0, {}, catalogue=True)
            data = multiworld.worlds[1].fill_slot_data()
            unlock_ids = data["unlock_ids"]
            if len(unlock_ids) < 300 or data["checks"] != len(unlock_ids) \
                    or len(multiworld.get_locations(1)) != 2 * len(unlock_ids):
                raise AssertionError("Default catalogue did not expand shipments and natural locations")
            for identifier in unlock_ids:
                natural = next(location for location in multiworld.get_locations(1)
                               if location.address == 402970000 + identifier)
                if not natural.locked or natural.item.code != 402960000 + identifier \
                        or natural.item.player != 1:
                    raise AssertionError("Natural unlock is not a fixed matching self-reward")
            multiworld = generate(2, {}, three_players=True)
            location = multiworld.get_location("Shop Shipment 002", 1)
            if location.item.player != 2:
                raise AssertionError("Cross-player fixture was not placed as requested")
            archive = output / f"AP_{multiworld.seed_name}.zip"
            live_test(runtime, godot, archive, directory)
            multiworld = generate(10, {"remote_characters": True})
            ids = multiworld.worlds[1].fill_slot_data()["unlock_ids"]
            delivery_item = next(name for name, code in world_type.item_name_to_id.items()
                                 if code == 402960000 + ids[0])
            multiworld = generate(10, {"remote_characters": True, "required_victories": 1}, three_players=True)
            live_test(runtime, godot, output / f"AP_{multiworld.seed_name}.zip", directory, unlocks=True)
            print("MULTIWORLDGG_TEST generation_boundaries=true sources=true death_link=true live=true", flush=True)
    finally:
        world_archive.unlink()


def live_test(runtime: Path, godot: str, archive: Path, directory: Path, unlocks: bool = False) -> None:
    from websockets.sync.client import connect

    archive.with_suffix(".apsave").unlink(missing_ok=True)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    endpoint = f"ws://127.0.0.1:{port}"
    with (directory / "server.log").open("w+") as log:
        server = subprocess.Popen(
            # The child also needs unittest loaded to activate AP_TEST_WORLDS.
            [sys.executable, "-c",
             "import runpy, sys, unittest; "
             "sys.argv = sys.argv[1:]; runpy.run_path(sys.argv[0], run_name='__main__')",
             str(runtime / "MultiServer.py"), str(archive),
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
            if unlocks:
                with connect(endpoint, open_timeout=3) as websocket:
                    websocket.recv(timeout=3)
                    websocket.send(json.dumps([{
                        "cmd": "Connect", "game": "Pathogenic", "name": "Pathogenic1",
                        "uuid": "unlock-delivery-test", "password": None, "items_handling": 7,
                        "tags": ["AP"], "version": {"major": 0, "minor": 6, "build": 0, "class": "Version"},
                    }]))
                    while not any(packet.get("cmd") == "Connected"
                                  for packet in json.loads(websocket.recv(timeout=5))):
                        pass
                    websocket.send(json.dumps([{"cmd": "LocationChecks", "locations": [402938002]}]))
                    while not any(packet.get("cmd") == "RoomUpdate"
                                  for packet in json.loads(websocket.recv(timeout=5))):
                        pass
            engine_tests(godot, endpoint, unlocks=unlocks)
            server.communicate("/exit\n".encode(), timeout=15)
            if server.returncode:
                raise RuntimeError(f"MultiworldGG test server exited with {server.returncode}")
            from Utils import restricted_loads
            saved = restricted_loads(zlib.decompress(archive.with_suffix(".apsave").read_bytes()))
            if not unlocks and saved["client_game_state"].get((0, 1)) != 30:
                raise AssertionError("Server did not persist the sender's completed goal")
            if not unlocks and not {402938001, 402938002}.issubset(saved["location_checks"].get((0, 1), set())):
                raise AssertionError("Server did not persist both confirmed checks")
            if unlocks and not any(402970000 <= location < 402980000
                                   for location in saved["location_checks"].get((0, 2), set())):
                raise AssertionError("Server did not persist the optional natural unlock")
            if unlocks and saved["client_game_state"].get((0, 2)) != 30:
                raise AssertionError("Server did not persist the victory-gated goal")
            print(f"MULTIWORLDGG_TEST unlocks={unlocks} server_checks_persisted=true", flush=True)
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
