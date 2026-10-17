# Pathogenic Demo: Archipelago Shop

Experimental macOS integration for **Steam demo 4029380, build 25697109**.
This project contains original mod and APWorld code, not the game's code or assets.
See [EVIDENCE.md](EVIDENCE.md) for the shop investigation and verification boundaries.

## What it does

Ordinary bodypart/mutation shop offers become numbered Archipelago location checks.
The displayed offer identifies the item and recipient. Buying it pays the normal
coin price and sends a location check instead of granting that pedestal's local
upgrade. Archipelago decides which player's item is at that location.

- A persistent campaign spans multiple demo runs: default 20 purchases, configurable
  from 5 to 100 in the YAML.
- Every eligible pedestal offers the **next** unpurchased shipment. They are not
  separate persistent pedestal locations. Rerolling does not add checks.
- Blood deals, choose-one rewards, mixed consumable offers and non-shop rewards
  retain vanilla behavior.
- Eligible purchases require a connection, valid slot data and a scouted item.
  They are blocked offline or after the campaign is exhausted.
- Killing the shopkeeper does **not** make AP shipments free: those offers retain
  their AP purchase price.
- Received Research Grants are banked. Use F8's redemption button during a living
  run to claim **15 coins per grant**.
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
- GDRE Tools 2.7.4 executable, supplied explicitly.
- The supported, unmodified Steam demo installation.

```bash
./build-install.sh --verify --gdre "/absolute/path/to/Godot RE Tools"
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
   Use a unique player name and adjust `shop_checks`. Add the other players' YAMLs.
3. Generate a seed and host its `.archipelago` multidata using Archipelago
   MultiServer. A public generator need not have this custom world installed;
   use a local/custom-world-capable generator.
4. Start [launch-modded.command](launch-modded.command), **not Steam's normal
   Play shortcut**, which still starts the unmodded game.
5. Press F8. Enter `ws://host:port` (or `wss://host:port`), the exact generated slot
   name and optional server password. Click Connect.
6. Start a run, earn coins and buy eligible shop shipments. The overlay reports
   server confirmation. Redeem received grants when useful.

The server address and slot name are saved; the password is not. F8 hides/shows
the panel. There is no automatic reconnection after a lost connection; use F8.

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
acknowledgment and item replay.

An opt-in destructive-to-its-test-slot live test requires a **fresh test seed**:
two slots named `Pathogenic1` and `Pathogenic2`, with player 1's shipment 2 addressed
to player 2. It buys shipments 1 and 2. Do not run against a real campaign.

```bash
python3 tools/test.py --godot "/path/to/Godot" \
  --live-server ws://127.0.0.1:38289
```

The actual game engine has verified bootstrap loading, separate-save routing and
extension of the actual packed shop scene. The real AP server has verified
cross-player delivery, confirmation, redemption and reconnect replay using the
production client with original game-state test doubles. **A full interactive
run, visual F8 operation, actual shop entry and vanilla save/reload behavior have
not been verified.** Treat this as an experimental implementation, not a finished
gameplay-certified release. Native headless logs contain engine/resource and
disabled-Sentry initialization errors; the smoke requires no GDScript errors,
the expected hook marker and successful exit, not a completely clean engine log.

Before relying on a campaign, manually check the overlay, one paid shipment,
absence of its local upgrade, AP receipt, and save/reload in a disposable seed.
