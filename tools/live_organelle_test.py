#!/usr/bin/env python3
"""Live in-game test of remote organelle deliveries (macOS, local Steam install).

Drives the real game with keyboard/mouse events and reads the mod's debug state file.

  python3 tools/live_organelle_test.py run          # full scenario, then restores everything
  python3 tools/live_organelle_test.py setup        # build, install, seed, server, launch game
  python3 tools/live_organelle_test.py state|shot NAME|key NAME|click X Y|send ID|enter-run
  python3 tools/live_organelle_test.py teardown     # stop game/server, restore mod + config

`setup` and `teardown` persist their state in WORK/session.json so the subcommands can be
used interactively. Requires Accessibility and Screen Recording permission for the terminal.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
HOME = Path.home()
GAME_APP = HOME / "Library/Application Support/Steam/steamapps/common/Pathogenic/Pathogenic.app"
WORKSHOP_ZIP = HOME / ("Library/Application Support/Steam/steamapps/workshop/content/3808690/3821496115/"
                       "ViMaSter-MultiworldGGShop.zip")
USER_DIR = HOME / "Library/Application Support/Godot/app_userdata/Pathogenic/multiworldgg_shop"
MWGG = ROOT.parent / "MultiWorldGG/.cache"
WORK = Path("/tmp/pathogenic-live")
SESSION = WORK / "session.json"
DEBUG_FLAG = USER_DIR / "debug_state.flag"
DEBUG_STATE = USER_DIR / "debug_state.json"
CLIENT_LOG = USER_DIR / "client.log"
SLOT = "PathogenicLive"
HIDDEN = 3  # G.EditorState.HIDDEN
KEYS = {"escape": 53, "enter": 36, "tab": 48, "space": 49, "up": 126, "down": 125, "left": 123,
        "right": 124, "w": 13, "a": 0, "s": 1, "d": 2, "e": 14}

sys.path.insert(0, str(ROOT))


def log(message: str) -> None:
    print(f"[live] {message}", flush=True)


def load_session() -> dict:
    return json.loads(SESSION.read_text()) if SESSION.is_file() else {}


def save_session(session: dict) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    SESSION.write_text(json.dumps(session, indent=2))


def helper() -> Path:
    binary = WORK / "input"
    source = ROOT / "tools/live/input.swift"
    if not binary.exists() or binary.stat().st_mtime < source.stat().st_mtime:
        WORK.mkdir(parents=True, exist_ok=True)
        subprocess.run(["swiftc", "-O", "-o", str(binary), str(source)], check=True)
    return binary


def input_cmd(*args) -> str:
    return subprocess.run([str(helper()), *map(str, args)], check=True, capture_output=True,
                          text=True).stdout


def game_window() -> dict | None:
    windows = [w for w in json.loads(input_cmd("windows", "Pathogenic")) if w["layer"] == 0]
    return max(windows, key=lambda w: w["bounds"]["Width"] * w["bounds"]["Height"]) if windows else None


def activate() -> None:
    window = game_window()
    if window is None:
        raise RuntimeError("Pathogenic window not found")
    input_cmd("activate", window["pid"])


def key(name: str, hold_ms: int = 60) -> None:
    activate()
    input_cmd("key", KEYS[name], hold_ms)
    time.sleep(0.25)


def click(x: float, y: float) -> None:
    activate()
    input_cmd("click", x, y)
    time.sleep(0.3)


def screenshot(name: str) -> Path:
    activate()
    window = game_window()
    path = WORK / "shots" / f"{name}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["screencapture", "-x", "-o", "-l", str(window["id"]), str(path)], check=True)
    log(f"screenshot {path}")
    return path


def state() -> dict:
    for _ in range(20):
        try:
            return json.loads(DEBUG_STATE.read_text())
        except (OSError, ValueError):
            time.sleep(0.1)
    return {}


def wait_for(predicate, description: str, timeout: float = 30.0, interval: float = 0.25) -> dict:
    deadline = time.monotonic() + timeout
    current = {}
    while time.monotonic() < deadline:
        current = state()
        if current and predicate(current):
            return current
        time.sleep(interval)
    raise AssertionError(f"Timed out waiting for {description}; last state: {json.dumps(current)}")


def organelle_pool() -> dict:
    data = json.loads((ROOT / "apworld/pathogenic/organelles.json").read_text())
    return {entry["id"]: entry for entry in data["entries"]}


# --- environment -----------------------------------------------------------------------------

def setup(port: int) -> dict:
    session = load_session()
    if session.get("active"):
        raise RuntimeError(f"A live session is already active; run teardown first ({SESSION})")
    if game_window() is not None:
        raise RuntimeError("Pathogenic is already running; close it first")
    runtime_source = next(MWGG.glob("runtime-*"))
    python = next(MWGG.glob("venv-*/bin/python"))
    WORK.mkdir(parents=True, exist_ok=True)
    session = {"active": True, "port": port}
    save_session(session)

    log("building mod and APWorld")
    subprocess.run([sys.executable, str(ROOT / "tools/build.py")], check=True, cwd=ROOT,
                   stdout=subprocess.DEVNULL)

    backup = WORK / "backup"
    backup.mkdir(exist_ok=True)
    shutil.copy2(WORKSHOP_ZIP, backup / "workshop.zip")
    shutil.copy2(USER_DIR / "connection.cfg", backup / "connection.cfg")
    session["backup"] = str(backup)
    save_session(session)
    shutil.copy2(ROOT / "dist/ViMaSter-MultiworldGGShop.zip", WORKSHOP_ZIP)
    log("installed dist/ViMaSter-MultiworldGGShop.zip over the Workshop copy (backup kept)")

    runtime = WORK / "runtime"
    if not runtime.exists():
        shutil.copytree(runtime_source, runtime, symlinks=True)
    for old in (runtime / "custom_worlds").glob("*.apworld"):
        old.unlink()
    shutil.copy2(ROOT / "dist/pathogenic.apworld", runtime / "custom_worlds/pathogenic.apworld")
    players = WORK / "players"
    output = WORK / "output"
    for directory in (players, output):
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir()
    (players / "live.yaml").write_text(json.dumps({"name": SLOT, "game": "Pathogenic", "Pathogenic": {
        "remote_characters": False, "remote_plasmids": False, "remote_loadouts": False,
        "remote_organelles": True, "coin_checks": 0, "death_link": False,
    }}))
    log("generating an organelle-only seed")
    environment = {**os.environ, "SKIP_REQUIREMENTS_UPDATE": "1"}
    subprocess.run([str(python), "Generate.py", "--player_files_path", str(players), "--outputpath",
                    str(output), "--spoiler", "0"], cwd=runtime, env=environment, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    archive = next(output.glob("AP_*.zip"))

    fifo = WORK / "server.fifo"
    if fifo.exists():
        fifo.unlink()
    os.mkfifo(fifo)
    server_log = (WORK / "server.log").open("w")
    server = subprocess.Popen([str(python), "-u", "MultiServer.py", str(archive), "--host", "127.0.0.1",
                               "--port", str(port)], cwd=runtime, env=environment,
                              stdin=os.open(fifo, os.O_RDWR), stdout=server_log, stderr=subprocess.STDOUT,
                              start_new_session=True)
    session["server_pid"] = server.pid
    save_session(session)
    deadline = time.monotonic() + 120
    while "server listening" not in (WORK / "server.log").read_text().lower():
        if server.poll() is not None or time.monotonic() > deadline:
            raise RuntimeError("MultiworldGG server did not start; see " + str(WORK / "server.log"))
        time.sleep(0.5)
    log(f"server listening on 127.0.0.1:{port} ({archive.name})")

    (USER_DIR / "connection.cfg").write_text(
        f'[connection]\n\nserver="127.0.0.1:{port}"\nslot="{SLOT}"\n\n[mod]\n\nenabled=true\n\n'
        "[sources]\n\nshops=true\nitem_rooms=true\nboss_rewards=true\nlevel_ups=true\n")
    DEBUG_FLAG.write_text("1")
    DEBUG_STATE.unlink(missing_ok=True)
    session["log_offset"] = CLIENT_LOG.stat().st_size if CLIENT_LOG.exists() else 0
    save_session(session)

    log("launching Pathogenic")
    subprocess.run(["open", "-n", str(GAME_APP)], check=True)
    deadline = time.monotonic() + 90
    while game_window() is None:
        if time.monotonic() > deadline:
            raise RuntimeError("Pathogenic window did not appear")
        time.sleep(1)
    session["game_pid"] = game_window()["pid"]
    save_session(session)
    wait_for(lambda s: s.get("synchronized"), "the client to connect and synchronize", 120)
    log("game connected and synchronized")
    return session


def teardown() -> None:
    session = load_session()
    window = game_window()
    # Steam relaunches the game, so the window's process can differ from the launched one.
    for pid in {session.get("game_pid"), window["pid"] if window else None} - {None}:
        try:
            os.kill(pid, signal.SIGTERM)
            for _ in range(40):
                os.kill(pid, 0)
                time.sleep(0.25)
        except ProcessLookupError:
            pass
    if session.get("server_pid"):
        try:
            os.killpg(session["server_pid"], signal.SIGTERM)
        except ProcessLookupError:
            pass
    backup = Path(session["backup"]) if session.get("backup") else None
    if backup and (backup / "workshop.zip").exists():
        shutil.copy2(backup / "workshop.zip", WORKSHOP_ZIP)
        log("restored the Workshop mod copy")
    if backup and (backup / "connection.cfg").exists():
        shutil.copy2(backup / "connection.cfg", USER_DIR / "connection.cfg")
        log("restored connection.cfg")
    DEBUG_FLAG.unlink(missing_ok=True)
    DEBUG_STATE.unlink(missing_ok=True)
    session["active"] = False
    save_session(session)


def send(organelle_id: int) -> str:
    name = "Organelle: " + organelle_pool()[organelle_id]["name"]
    with open(WORK / "server.fifo", "w") as fifo:
        fifo.write(f"/send {SLOT} {name}\n")
    log(f"server: /send {SLOT} {name}")
    return organelle_pool()[organelle_id]["resource"]


def client_log() -> str:
    offset = load_session().get("log_offset", 0)
    with CLIENT_LOG.open() as file:
        file.seek(offset)
        return file.read()


# --- navigation --------------------------------------------------------------------------------

def click_window(fx: float, fy: float) -> None:
    """Click at a fraction of the game window (menus scale with the window)."""
    bounds = game_window()["bounds"]
    click(bounds["X"] + bounds["Width"] * fx, bounds["Y"] + bounds["Height"] * fy)


def enter_run(timeout: float = 180) -> dict:
    """From the main menu, start a MultiworldGG run and wait until the player has control."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        current = state()
        scene = current.get("scene", "")
        if current.get("in_control"):
            return current
        if scene.endswith("main_menu.tscn"):
            key("escape")  # skips the intro animation
            key("up")  # wakes the faded menu
            log("main menu: Play")
            click_window(0.125, 0.514)
            time.sleep(2.0)
        elif scene.endswith("player_selection_menu.tscn"):
            # Character "Select", then "Start" twice (the second confirms the MultiworldGG warning).
            log("character/loadout menu: Select/Start")
            click_window(0.5, 0.878)
            time.sleep(1.5)
        else:
            time.sleep(0.5)  # loading, intro video or spawn animation
    raise AssertionError(f"Could not reach player control; last state: {json.dumps(state())}")


def recycle_held() -> None:
    rect = state().get("recycle_button") or []
    if len(rect) != 4:
        raise AssertionError(f"Recycle button not visible: {json.dumps(state())}")
    click(rect[0] + rect[2] / 2, rect[1] + rect[3] / 2)


# --- scenario ----------------------------------------------------------------------------------

def scenario() -> None:
    pool = organelle_pool()
    first, second = 1, 2
    enter_run()
    log("player has control")
    for name in ("w", "d", "s", "a"):
        key(name, 300)
    wait_for(lambda s: s["in_control"] and not s["pending"], "control with an empty queue")
    screenshot("0-in-control")

    first_resource = send(first)
    current = wait_for(lambda s: s["held"] == first_resource and s["editor_state"] != HIDDEN,
                       "the editor to open holding the first organelle", 20)
    time.sleep(1.5)
    current = state()
    assert not current["in_control"] and current["editor_active"], current
    log(f"editor open holding {pool[first]['name']} ({current['held']})")
    screenshot("1-first-delivery")

    second_resource = send(second)
    wait_for(lambda s: second_resource in s["pending"], "the second organelle to be queued", 20)
    time.sleep(3.0)
    current = state()
    assert current["held"] == first_resource and current["editor_active"], current
    assert current["pending"] == [first_resource, second_resource], current
    log(f"second organelle queued; editor still holds {pool[first]['name']}")
    screenshot("2-second-queued")

    recycle_held()
    wait_for(lambda s: s["held"] == "", "the first organelle to leave the hand", 10)
    key("tab")
    closed = wait_for(lambda s: s["editor_state"] == HIDDEN and s["in_control"],
                      "the editor to close after recycling", 15)
    closed_at = time.monotonic()
    assert closed["pending"] == [second_resource] and closed["delivered"] == 1, closed
    log("first delivery completed; waiting for the second")
    screenshot("3-between-deliveries")
    current = wait_for(lambda s: s["held"] == second_resource and s["editor_state"] != HIDDEN,
                       "the editor to reopen with the second organelle", 15, 0.1)
    gap = time.monotonic() - closed_at
    # The game measures the uninterrupted control time; the host side only observes it late.
    assert current["last_wait_msec"] >= 2000 and gap >= 1.5, (gap, current)
    log(f"editor reopened with {pool[second]['name']} after {current['last_wait_msec']} ms of control "
        f"({gap:.1f}s observed)")
    time.sleep(1.5)
    screenshot("4-second-delivery")

    recycle_held()
    wait_for(lambda s: s["held"] == "", "the second organelle to leave the hand", 10)
    key("tab")
    current = wait_for(lambda s: s["editor_state"] == HIDDEN and s["in_control"],
                       "control after the second delivery", 15)
    assert current["pending"] == [] and current["delivered"] == 2, current
    time.sleep(3.0)
    current = state()
    assert current["in_control"] and current["editor_state"] == HIDDEN and current["held"] == "", current
    for name in ("a", "w"):
        key(name, 300)
    screenshot("5-back-in-control")

    text = client_log()
    for expected in (f"Opened editor with organelle {pool[first]['name']} (0 more queued)",
                     f"Delivered organelle {pool[first]['name']} (1 queued)",
                     f"Opened editor with organelle {pool[second]['name']} (0 more queued)",
                     f"Delivered organelle {pool[second]['name']} (0 queued)"):
        assert expected in text, f"client.log is missing: {expected}"
    log("LIVE_ORGANELLE_TEST passed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["run", "setup", "teardown", "state", "shot", "key", "click",
                                            "send", "enter-run", "scenario", "log"])
    parser.add_argument("args", nargs="*")
    parser.add_argument("--port", type=int, default=38291)
    parser.add_argument("--keep", action="store_true", help="leave game and server running after `run`")
    options = parser.parse_args()
    command, args = options.command, options.args
    if command == "run":
        try:
            setup(options.port)
            scenario()
        finally:
            if not options.keep:
                teardown()
    elif command == "setup":
        setup(options.port)
    elif command == "teardown":
        teardown()
    elif command == "state":
        print(json.dumps(state(), indent=2))
    elif command == "shot":
        screenshot(args[0] if args else "manual")
    elif command == "key":
        for name in args:
            key(name)
    elif command == "click":
        click(float(args[0]), float(args[1]))
    elif command == "send":
        send(int(args[0]))
    elif command == "enter-run":
        enter_run()
    elif command == "scenario":
        scenario()
    elif command == "log":
        print(client_log())


if __name__ == "__main__":
    main()
