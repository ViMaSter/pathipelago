# Pathogenic Demo: Archipelago Shop

Experimental macOS integration for **Steam demo 4029380, build 25697109**.
This project contains original mod and APWorld code, not the game's code or assets.
See [EVIDENCE.md](EVIDENCE.md) for the shop investigation and verification boundaries.

## What it does

Remote unlocks can appear in four places, each switched on or off in the YAML (see
[Player options](#player-options)). With every source on, every shop room (normal and heart shop)
gets **exactly one designated Archipelago pedestal**, chosen deterministically (first ordinary bodypart offer by node name,
else the first non-blood pedestal). It keeps the normal coin price, but always shows
the **Enhancer** icon (`res://gfx/player/bodyparts/internal/upgrade.png`) instead of
the rolled upgrade. Its floating name becomes **Remote Unlock 3/20** (next shipment of the
campaign), and its tooltip becomes a blue **ARCHIPELAGO** card titled the same way
whose text is only the scouted item, recipient player and game, for example
`"Poke Ball" for PkmnPlayer (Pokemon Red and Blue)` with the three names in blue.
This is possible because Archipelago fixes each location's item at generation time
and the client scouts it (`LocationScouts`). Buying it pays coins, grants **nothing locally**,
and sends the location check. Archipelago then delivers the item to its owner.

Blue **item rooms** (`item_room`, `item_room_1_item`, `item_room_2_item`: one to three
free choose-one pedestals) also get exactly one remote unlock, the first pedestal in
scene order. It looks the same (Enhancer icon, "Remote Unlock n/N", blue tooltip),
costs nothing, and taking it sends the next check instead of the free upgrade and
consumes the other choices, as picking any item there does. In a one-item room the
only pedestal is the remote unlock.

**Boss rewards** work the same way. The skin, stomach, intestine and liver bosses drop a
choose-one bodypart selection (`bodypart_reward_3_choice`). Its first pedestal becomes a free
remote unlock, and the other choices stay vanilla. The money drop and devil teleport are
not affected. The heart boss drops only money and the brain boss drops nothing, so
neither has a remote unlock.

**Level-up drafts** ("Select a mutation") replace their last card with a remote unlock
(the empty helix card with the Enhancer icon). Its tooltip reads "Remote Unlock n/N". On
evolution levels (2, 6 and 10) this is the skip card. Picking it sends the next check and
fills the level's gene the way skipping does. The other cards stay vanilla, and every
reroll or new level gets a fresh remote unlock.

### Turning Archipelago on (per run)

The mod is **off by default**. Turn on **Enable Archipelago for new runs** in
Settings > Archipelago (main menu or pause menu). Then start a run.

The mode is fixed when a run starts and stays fixed for that run:

- A run started while the setting is off stays vanilla. It shows no remote unlocks and pays out no
  grants, even if you turn the setting on mid-run. The setting then applies to the next run.
- A run started while the setting is on stays an Archipelago run, even if you turn it off or
  lose the connection. While disconnected, remote unlocks stay in place but are blocked
  with a warning until you reconnect.
- **Continue Run** restores the mode the run started with. The client stores it in
  `archipelago_shop/run.cfg`, keyed by the run seed. A saved run it does not recognize continues vanilla.

The game fixes every roll of a run (level layout, rewards, shop stock, drafts) from the
run seed (`G.rng_seed`), which is set when the run starts. Remote unlocks do not change those
rolls; they only take over one existing choice. The client connects automatically
on launch only when the setting is on.

### Player options

| YAML option | Default | Remote unlock location |
| --- | --- | --- |
| `shop_checks` | 20 | Number of checks (5-100) across all runs |
| `shop_unlocks` | true | One coin pedestal in every shop |
| `item_room_unlocks` | true | One free pedestal in every blue item room |
| `boss_reward_unlocks` | true | One choice of every boss bodypart reward |
| `level_up_unlocks` | true | Last card of every level-up mutation draft |

At least one source must be true; generation fails otherwise. Disabled sources are
completely vanilla. The client receives the sources in slot data (schema 2) and remembers
them in `connection.cfg` for offline play. The Archipelago tab lists them under the
check counter. Seeds generated before these options (schema 1) enable every source.
The core `progression_balancing` and `accessibility` options are hidden. The world has only
filler items and every location is always reachable, so they cannot change a seed.
[PathogenicDemo.yaml](PathogenicDemo.yaml) currently enables only blue item rooms.

- A persistent campaign spans multiple demo runs: default 20 purchases, configurable
  from 5 to 100 in the YAML.
- The AP pedestal offers the **next** unpurchased shipment. Rerolling does not add checks.
- All other pedestals, blood deals and other rewards (boss, chest, devil) retain vanilla behavior.
- The AP purchase requires a connection, valid slot data and a scouted item. It is
  blocked offline (toast + log line) and becomes vanilla after the campaign is exhausted.
- Killing the shopkeeper does **not** make the AP shipment free.
- After a save/reload, a shop whose AP pedestal was already bought may designate
  another pedestal (so each shop has *at least* one).
- Received Research Grants are redeemed automatically for **15 coins each** as soon
  as they arrive (including ones another player unlocks), announced in the same blue
  `Archipelago: received 1 Research Grant: +15 coins` text as a purchase. Grants that
  arrive with no living run wait in the journal and are paid 2 s after the next run's
  player exists.
- All server-confirmed campaign checks trigger Archipelago goal status.
- No DeathLink, boss goal, progression unlocks or run-completion requirement.

This APWorld is a **filler-only purchase campaign**, not a progression randomizer.
All shipment locations are logically reachable from the start, assuming repeated
runs can earn money and reach shops. The generator's completion condition is
therefore logically available immediately; the client reports actual completion
only after the server confirms every purchase. Mixing with other games is
supported by the AP protocol, but the executed live test used two Pathogenic slots.

## Build and install

Quit the game first. Keep Steam running.

Requirements:

- Python 3.11 or newer for tooling (`python3` by default).
- Godot 4.7 for isolated tests; tested with 4.7 stable Mono.
- GDRE Tools 2.7.4, installed at `/Applications/Godot RE Tools.app`.
  For another location, set `GDRE` or pass `--gdre` with its executable path.
- The supported, unmodified Steam demo installation.

```bash
./build-install.sh --verify
```

`--verify` opens Steam's verification URI. **Wait for Steam to finish**, then type
`VERIFIED` in the terminal. Opening that URI is not proof of successful verification.
Without the flag, verification is skipped explicitly.

The script tests and builds the original-code archives, verifies the installed
game's executable/PCK hashes, builds a **fresh private app copy**, patches only that
copy's project configuration/bootstrap, runs its native bootstrap/packed-shop smoke
test, and atomically publishes [launch-modded.command](launch-modded.command).
If a build or smoke test fails, an existing working launcher is preserved and the
failed build/logs remain available for diagnosis.

The demo disables its bundled Mod Loader outside the full game. Merely copying a
ZIP into Steam's mods directory will not activate this demo. The private copy
retains the demo's app ID; it does not impersonate the full game.

**Nothing in the official installation, original saves or other mods is cleared.**
Fresh private builds avoid stale mod files without deleting unrelated data. Old
private builds are intentionally retained. This differs from a destructive
"clear out the game" install.

Additional options:

```bash
./build-install.sh --build-only
./build-install.sh --godot "/path/to/Godot" --gdre "/path/to/GDRE" \
  --game "/path/to/Pathogenic.app"
```

`GODOT`, `GDRE` and `PYTHON` environment variables are also supported.
Steam updates fail the supported-build fingerprint check; do not bypass it.

## Generate and host a multiworld

1. Install [dist/pathogenic_demo.apworld](dist/pathogenic_demo.apworld) into an
   Archipelago installation that supports custom worlds; tested with AP 0.6.7.
   Restart the generator after installation.
2. Copy [PathogenicDemo.yaml](PathogenicDemo.yaml) into its `Players` directory.
   Use a unique player name and adjust `shop_checks` and the unlock-source options.
   Add the other players' YAMLs.
3. Generate a seed and host its `.archipelago` multidata using Archipelago
   MultiServer. A public generator need not have this custom world installed;
   use a local/custom-world-capable generator.
4. Start [launch-modded.command](launch-modded.command), **not Steam's normal
   Play shortcut**, which still starts the unmodded game.
5. Open **Settings > Archipelago** (the tab after Remap, in the main or pause
   menu). Turn on **Enable Archipelago for new runs**. Enter `ws://host:port` (or `wss://host:port`), the exact generated slot
   name and optional server password. Click Connect.
6. Start a **new** run (runs started while the setting was off stay vanilla), earn coins and buy the blue-tooltip AP pedestal in each shop. The
   tab reports checks confirmed by the server. Received grants pay out automatically.

The server address and slot name are saved; the password is not. There is no
automatic reconnection after a lost connection; reconnect from the tab.

### Logs

| Log | Path |
| --- | --- |
| AP client (flushed, every shop pick and server message) | `~/Library/Application Support/Pathogenic Archipelago/archipelago_shop/client.log` (rotates to `client.log.1`) |
| Godot engine / game | `~/Library/Application Support/Pathogenic Archipelago/logs/godot.log` |
| Local WebHost room server | room page > "Server log", or `$SESSION_FILES/ap-runtime/logs/83166e17-24c7-4995-ba5b-18fde871dcc4.txt` |
| Standalone MultiServer | `$SESSION_FILES/ap-runtime/logs/Server_*.txt` |

The Archipelago tab shows the last 200 client log lines and has an "Open log
folder" button. Each pick logs `Shop pick <room>/<item> cost ... -> ARCHIPELAGO`
or `-> vanilla local purchase`.

### Exact local walkthrough: Pokemon plus Pathogenic

These paths describe Vincent's current machine. The generator and Python
environment below were prepared during integration testing; keep them available.
The prepared runtime now contains both Pathogenic and Pokemon support.

First distinguish the files:

- `PathogenicDemo.yaml`: player settings, already provided; no generation needed.
- `dist/pathogenic_demo.apworld`: the custom game plugin, already built. Install
  it in the generator, not on the hosting website.
- `AP_<seed>.zip`: the generated multiworld containing both players. Upload this
  to https://archipelago.gg/uploads. That page also accepts `.archipelago`
  multidata; it does not install `.apworld` plugins or generate from YAML.

#### 1. Prepare the generator and player files

Run the following in Terminal. `SESSION_FILES` is the exact existing location,
not a placeholder. The commands copy the two required Pokemon modules from the
existing AP 0.6.7 source into the small test runtime. No download is needed.
The copy commands replace same-named files if you repeat this setup.

```bash
SESSION_FILES="$SESSION_FILES"
AP="$SESSION_FILES/ap-runtime"
SOURCE="$SESSION_FILES/tools/Archipelago-0.6.7"
mkdir -p "$AP/custom_worlds"
ditto "$SOURCE/worlds/pokemon_rb" "$AP/worlds/pokemon_rb"
ditto "$SOURCE/worlds/_bizhawk" "$AP/worlds/_bizhawk"
cp "./dist/pathogenic_demo.apworld" \
  "$AP/worlds/pathogenic_demo.apworld"

mkdir -p "./players-pokemon-pathogenic"
cp "~/Downloads/PkmnPlayer.yaml" \
  "./players-pokemon-pathogenic/PkmnPlayer.yaml"
cp "./PathogenicDemo.yaml" \
  "./players-pokemon-pathogenic/PathogenicDemo.yaml"
```

Open `./players-pokemon-pathogenic/PathogenicDemo.yaml`
and change its first line to exactly:

```yaml
name: Pathogenic1
```

Leave `game: Pathogenic Demo` and its settings unchanged. The supplied Pokemon
file already uses `name: PkmnPlayer`; keep that name. The dedicated player folder
should contain just these two YAMLs, not the earlier two-Pathogenic test files.

#### 2. Plan for the Pokemon base ROM (needed to play, not generate)

Your downloaded YAML currently uses `game_version: random`, so generation can
select Red or Blue. AP 0.6.7 generates a procedural patch without reading a ROM.
You need a compatible, legally obtained US/Europe ROM only when applying the
generated patch to play. Provide the version matching `.apred` or `.apblue`.
AP's configured default filenames, relative to the runtime, are:

```text
$SESSION_FILES/ap-runtime/Pokemon Red (UE) [S][!].gb
$SESSION_FILES/ap-runtime/Pokemon Blue (UE) [S][!].gb
```

Alternatively, select your ROM when Archipelago requests it. Renaming an
incompatible ROM does not make it compatible. Do not upload a base ROM.

#### 3. Generate the combined seed

Run in Terminal:

```bash
SESSION_FILES="$SESSION_FILES"
cd "$SESSION_FILES/ap-runtime"
SKIP_REQUIREMENTS_UPDATE=1 "$SESSION_FILES/ap311/bin/python" Generate.py \
  --player_files_path "./players-pokemon-pathogenic" \
  --outputpath "./dist/multiworld"
```

This uses the existing Python 3.11 environment, not the system's Python 3.14.
Wait for successful completion and the final archive message. If generation
fails, resolve the reported error; do not upload an old test archive instead.
Mixed generation was successfully executed with your YAML on October 17, 2026,
producing `AP_72893771011827805672.zip` and a Red patch without a base ROM.
The current seed, `AP_69318679617106091104.zip`, enables only blue item room remote unlocks.

The output is `./dist/multiworld/AP_<seed>.zip`.
The exact numeric filename is printed by the generator and cannot be known
before generation. Open that exact output directory in Finder:

```bash
open "./dist/multiworld"
```

#### 4. Upload and connect

1. At https://archipelago.gg/uploads select the newly generated `AP_<seed>.zip`,
   then create a room from that seed.
2. Check its tracker lists **Pathogenic1 / Pathogenic Demo** and
   **PkmnPlayer / Pokemon Red and Blue**.
3. Launch `./launch-modded.command` and open
   Settings > Archipelago.
4. Use slot name **Pathogenic1**. If the new room says
   `/connect archipelago.gg:12345`, enter **ws://archipelago.gg:12345**.
   Replace `12345` with the port on the new room page. Do not enter the HTTPS
   room URL, a numeric slot ID, or the old room's port.
5. The Pokemon player downloads their generated patch from the seed/room page,
   follows the Pokemon client setup, and connects as **PkmnPlayer**.

The actual new connection URL is only available after creating the room.
The old `archipelago.gg:63477` room lacks Pathogenic and cannot gain another
world just by changing the connection name.

To regenerate, repeat step 3 without `--seed` to request a fresh random seed,
then upload the new ZIP and create a new room. Steps 1 and 2 need repeating only
when their inputs change. Neither rebuilding the mod nor making a new APWorld
plugin is necessary. Keep the journal for existing campaigns intact.

### Prepared local two-player server with room page and tracker

No website upload is needed for local hosting. The recommended launcher runs a
local copy of the archipelago.gg website (WebHost) with one room for the prepared
seed. It provides the room page, server log, slot trackers and the multiworld server:

```bash
"./start-local-webhost.command"
```

| Page | URL |
| --- | --- |
| Room (connect info, server log, patch downloads) | http://127.0.0.1:38280/room/gxZuFyTHSZW6Wxj96HHcxA |
| Multiworld tracker | http://127.0.0.1:38280/tracker/m7uTi9p4RNOZjF-PLH6a8g |
| Pathogenic1 tracker | http://127.0.0.1:38280/generic_tracker/m7uTi9p4RNOZjF-PLH6a8g/0/1 |

The IDs are created on first start and stored in `local-webhost/room.json`; the
launcher prints them. Room progress is stored in `local-webhost/ap.db3`, separate
from the standalone server's `.apsave`. Delete `local-webhost/` only to start the
room over. Both ports bind only to `127.0.0.1`, without a password. Starting the launcher
with a different campaign creates a new room and puts earlier rooms to sleep. Their
progress stays in the database, and the new room takes port 38281.

Alternatively, the plain server without website (do not run both, they share port 38281):

```bash
"./start-local-server.command"
```

The launchers depend on the prepared runtime and Python environment in the
session-files path above; keep those directories.

| Player | Client address | Slot name |
| --- | --- | --- |
| Pathogenic Demo | `ws://127.0.0.1:38281` | `Pathogenic1` |
| Pokemon Red and Blue | `127.0.0.1:38281` | `PkmnPlayer` |

Launch `launch-modded.command`, open Settings > Archipelago, and enter the Pathogenic address/name.
For Pokemon, the generated patch is:

```text
./dist/multiworld/AP_69318679617106091104_P2_PkmnPlayer.apred
```

Apply it using the Archipelago client with your compatible Pokemon Red ROM
(expected MD5 `3d45c1ee9abd5738df46d2bdda8b57dc`), then follow the Pokemon
Red/Blue BizHawk setup to launch and connect the game. The server is prepared;
the emulator/ROM and actual Pokemon gameplay are not installed or verified here.

The campaign and the standalone server's persistent progress are:

```text
./dist/multiworld/AP_69318679617106091104.zip
./dist/multiworld/AP_69318679617106091104.apsave
```

Keep both files and the Pathogenic journal to resume. Stop with `/exit` in the
server console or Ctrl+C. Restarting the launcher resumes this seed, not a new
one. For a fresh seed, repeat generation step 3, then supply its exact ZIP path
as the launcher's first argument. Old campaign saves are kept separately.

## Shop sprites

The pedestal shows a bodypart's `icon_texture` (internal organelles are drawn over
their `background_texture` pattern inside a sphere). Mutations with a nonzero
`reward_drop_rate` can also appear and use their `texture`. In the game PCK these
live under `res://gfx/player/bodyparts/` (external), `.../bodyparts/internal/`
(organelles), `.../internal/patterns/` (backgrounds) and `res://gfx/player/mutations/`,
named by the `.tres` resources in `res://scn/player/bodyparts/` and
`res://scn/player/mutations/all/` (`ui_name` keys resolved via
`res://translations/translations.csv`). To export them as `[ITEMNAME].png`:

```bash
python3 tools/export_shop_sprites.py
```

This writes `shop-sprites/` (gitignored; game assets, do not distribute) with
`backgrounds/[ITEMNAME].png` and `index.csv` mapping each file to its resource.

## Saves, removal and limits

The private app uses:

```text
~/Library/Application Support/Pathogenic Archipelago
```

The AP journal lives in its `archipelago_shop` subdirectory. It is keyed by
seed name, team and slot, persists purchases and redeemed item history, and resends
unacknowledged checks. Use only one running client per slot. Do not reuse a campaign
identity for a newly regenerated server or delete a journal to reset an active slot.

The AP journal and vanilla run save are **not one atomic transaction**. A crash
between purchase journaling and run saving can forgive a coin debit; a crash after
grant redemption but before run saving can lose those coins. Item-history replay
deduplication is tested, but exactly-once crash-safe currency is not guaranteed.

To stop using the mod, close it and launch normally through Steam. To reclaim
space, inspect `local-builds/*/build.json`, then manually remove only the specific
private build directories you no longer need and the generated launcher. Preserve
the separate save directory unless you deliberately want to lose modded progress.
No Steam restore is needed because the original installation is untouched.

**Never distribute `local-builds/`, recovered game files or a patched game PCK.**
Only the original-code mod ZIP/APWorld, source, YAML and tooling are distributable.

## Verification

```bash
python3 tools/test.py --godot "/path/to/Godot"
```

Tests cover deterministic packaging, guarded installation/configuration, failed
build publication, purchases, eligibility, offline refusal, journaling, check
acknowledgment, item replay, single-pedestal designation, the settings tab, the
log and the remote-unlock tooltip.

An opt-in destructive-to-its-test-slot live test requires a **fresh test seed**:
two slots named `Pathogenic1` and `Pathogenic2`, with player 1's shipment 2 addressed
to player 2. It buys shipments 1 and 2. Do not run against a real campaign.

```bash
python3 tools/test.py --godot "/path/to/Godot" \
  --live-server ws://127.0.0.1:38289
```

The actual game engine has verified bootstrap loading, separate-save routing,
the injected Settings > Archipelago tab, the remote-unlock tooltip, and that the
real `shop.tscn`/`heart_shop.tscn` designate one AP pedestal whose real pick signal
is routed to Archipelago (blocked offline, no local reward). The real AP server has
verified cross-player delivery, confirmation, redemption and reconnect replay using
the production client with original game-state test doubles. **A full interactive
run with an online paid shipment and vanilla save/reload behavior have not been
verified.** Treat this as an experimental implementation, not a finished
gameplay-certified release. Native headless logs contain engine/resource and
disabled-Sentry initialization errors; the smoke requires no GDScript errors,
the expected hook marker and successful exit, not a completely clean engine log.

Before relying on a campaign, check the tab, one paid shipment (client.log shows
`-> ARCHIPELAGO`, the tracker shows the check), absence of its local upgrade, and
save/reload in a disposable seed.

### Anti-cheat

Neither the demo (4029380) nor the full game (3808690) lists Valve Anti-Cheat in
its Steam categories, and the app bundles no anti-cheat component (only Steam API,
GodotSteam, Sentry, LimboAI and GoZen libraries). The mod uses no process
injection or debugger: it is GDScript loaded by the game's own Mod Loader in a
separate private copy with a separate save directory. The original install is untouched.
