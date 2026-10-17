#!/usr/bin/env python3
"""Run a loopback-only Archipelago WebHost with one room for a local campaign.

The room serves the multiworld on a fixed port and provides the same room,
tracker and log pages as archipelago.gg, backed by a local SQLite database.
"""

import argparse
import json
import logging
import multiprocessing
import os
import secrets
import sys
import uuid
import zipfile
from datetime import timedelta
from pathlib import Path

ROOM_TIMEOUT = 30 * 24 * 60 * 60


def loopback_server_process(name, ponyconfig, static_server_data, cert, key, host, *queues):
    # WebHost rooms bind every interface by default; keep them on HOST_ADDRESS.
    from WebHostLib import customserver

    original = customserver.WebHostContext.__init__

    def init(self, *args, **kwargs):
        original(self, *args, **kwargs)
        self.host = host

    customserver.WebHostContext.__init__ = init
    customserver.run_server_process(name, ponyconfig, static_server_data, cert, key, host, *queues)


def write_config(data: Path, web_port: int) -> None:
    config = data / "config.yaml"
    if config.exists():
        return
    key = secrets.token_hex(32)
    config.write_text(
        "SELFHOST: true\n"
        "SELFLAUNCH: true\n"
        "SELFGEN: false\n"
        "HOSTERS: 1\n"
        f"PORT: {web_port}\n"
        "HOST_ADDRESS: 127.0.0.1\n"
        f"MAX_ROOM_TIMEOUT: {ROOM_TIMEOUT}\n"
        f"UPLOAD_FOLDER: {json.dumps(str(data / 'uploads'))}\n"
        f"SECRET_KEY: {json.dumps(key)}\n"
        "PONY:\n"
        "  provider: sqlite\n"
        f"  filename: {json.dumps(str(data / 'ap.db3'))}\n"
        "  create_db: true\n"
    )


def ensure_room(app, data: Path, campaign: Path, room_port: int) -> dict:
    from pony.orm import commit, db_session
    from Utils import utcnow
    from WebHostLib.models import Room
    from WebHostLib.upload import upload_zip_to_db

    state_file = data / "room.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    with app.test_request_context(), db_session:
        room = Room.get(id=uuid.UUID(state["room"])) if state.get("campaign") == str(campaign) else None
        if room is None:
            owner = uuid.uuid4()
            with zipfile.ZipFile(campaign) as archive:
                seed = upload_zip_to_db(archive, owner=owner)
            if seed is None or isinstance(seed, str):
                raise SystemExit(f"WebHost rejected {campaign}: {seed}")
            room = Room(seed=seed, owner=owner, tracker=uuid.uuid4(), last_port=room_port, timeout=ROOM_TIMEOUT)
            commit()
            state = {"campaign": str(campaign), "seed": str(seed.id), "room": str(room.id),
                     "tracker": str(room.tracker), "owner": str(owner)}
            state_file.write_text(json.dumps(state, indent=2) + "\n")
        room.timeout = ROOM_TIMEOUT
        if room.last_port <= 0:
            room.last_port = room_port
        # Wakes the room on every launcher start.
        room.last_activity = utcnow()
        commit()
        state["port"] = room.last_port
    return state


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--data", required=True, type=Path)
    parser.add_argument("--campaign", required=True, type=Path)
    parser.add_argument("--web-port", type=int, default=38280)
    parser.add_argument("--room-port", type=int, default=38281)
    args = parser.parse_args()
    data = args.data.resolve()
    (data / "uploads").mkdir(parents=True, exist_ok=True)
    write_config(data, args.web_port)
    os.chdir(data)
    sys.path.insert(0, str(args.runtime.resolve()))
    os.environ.setdefault("SKIP_REQUIREMENTS_UPDATE", "1")

    import WebHost
    from WebHostLib import autolauncher
    from WebHostLib.autolauncher import autohost, stop
    from WebHostLib.options import create as create_options_files
    from worlds import AutoWorldRegister

    autolauncher.run_server_process = loopback_server_process

    app = WebHost.get_app()
    AutoWorldRegister.world_types = {name: world for name, world in AutoWorldRegister.world_types.items()
                                     if hasattr(world.web, "tutorials")}
    create_options_files()
    WebHost.copy_tutorials_files_to_static()
    state = ensure_room(app, data, args.campaign.resolve(), args.room_port)
    base = f"http://127.0.0.1:{app.config['PORT']}"
    from WebHostLib import to_url
    state["room"] = to_url(uuid.UUID(state["room"]))
    state["tracker"] = to_url(uuid.UUID(state["tracker"]))
    print(f"Local WebHost: {base}", flush=True)
    print(f"Room page:     {base}/room/{state['room']}", flush=True)
    print(f"Tracker:       {base}/tracker/{state['tracker']}", flush=True)
    print(f"Multiworld:    ws://127.0.0.1:{state['port']}", flush=True)
    autohost(app.config)
    from waitress import serve
    try:
        serve(app, host="127.0.0.1", port=app.config["PORT"], threads=app.config["WAITRESS_THREADS"])
    finally:
        stop()


if __name__ == "__main__":
    multiprocessing.freeze_support()
    multiprocessing.set_start_method("spawn")
    logging.basicConfig(format="[%(asctime)s] %(message)s", level=logging.INFO)
    main()
