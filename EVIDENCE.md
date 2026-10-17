# Shop rolls: evidence and design

## Artifact identity and method

Investigated the locally installed macOS Steam Pathogenic Demo, app ID 4029380,
build 25697109. Its project identifies version 1.2.1-dirty, commit
`ddfa31c81637eed9bbb00b5bd3c4a74c765e51b9`.

| Official file | SHA-256 |
| --- | --- |
| `Contents/MacOS/Pathogenic` | `0bf53c05712a1d60f54dbeb387d7f059c27cb94e08690bff067ee202b53e0370` |
| `Contents/Resources/Pathogenic.pck` | `8396febf677a23708da11dafe0deed353c2c2cb0709566eb725d0e2632c93ea4` |

REA inventoried the shipped application; GDRE Tools 2.7.4 privately recovered
scripts for static inspection. Recovered scripts are not included in this project.
The observations below are static derivations, not claims of runtime RNG tracing.

REA inventory record:
`ev_273026ff829d504788686e05d5297fb67448a57ff4048b09028dbb780f53b155`.

REA inspection record:
`ev_e3b9bf6a36dc5f8fc0ed55b2aa49302916f781918d6df63af47227fe9ae46427`.

The REA export (`evidence.json`) is retained locally, outside the repository.
These records establish artifact inventory, not automatic authentication of every
shop-function conclusion. Function evidence comes from the separately recovered
local scripts identified below.

## How a shop roll works

Paths below are resource paths within the game. Line anchors refer to recovered
scripts, not invented original-source provenance.

1. **Level reward stream** -- `scn/environ/level_generator.gd:51`.
   The reward RNG seed hashes the game RNG seed, the literal reward namespace,
   level number and an endless-tier suffix. The ordinary tier has no suffix;
   nonzero tiers append `_e<tier>`. Panic changes the level-generation stream,
   not this reward stream.

2. **Reward pool** -- `scn/environ/pickups/bodypart_reward.gd:80`.
   A reward uses its explicit pool or tag-selected pool; an empty tag uses Any.
   Resource/player drop weights and drop-rate modifiers apply. Devil deals apply
   additional modifiers, and eligible mutations join the Any pool. If the total
   usable weight is nonpositive, selection falls back to uniform weights.

3. **Weighted order, not a single roulette draw** -- `scn/utils.gd:255`.
   Candidates receive a randomized weighted permutation, ordered by descending
   `log(u) / weight`. Random draws use per-pool-index child seeds. Locked and
   nonpositive-weight entries are excluded. Thus resource ordering matters for
   deterministic results, even when the visible pool has the same members.

4. **Avoidance and fallback** -- `bodypart_reward.gd:80`.
   Selection skips the previous rerolled item and resources already present on
   the current reward/siblings. If every candidate is excluded, it falls back to
   the first ordered candidate. Avoidance therefore is not a hard guarantee of
   unique offers.

5. **Rarity and prefixes** -- `bodypart_reward.gd:226`.
   Rarity has its own seeded stream. Brain rewards are legendary unless
   overridden; otherwise rarity is drawn uniformly within permitted bounds.
   Prefix unlock/tutorial conditions gate separate 3% prefix chances; multiple
   prefixes can apply. Rarity upgrades use another independent stream. Restored
   or forced rarity bypasses the normal reroll upgrade.

6. **Price** -- `scn/environ/pickups/shop_item.gd:17`.
   The pedestal draws its seed from the level reward RNG. For ordinary coin
   offers, the pre-sale price is:

   ```text
   round(base_cost * (1 + (level_number - 1) / 4) * uniform(1.0, 1.3))
   ```

   A sale has probability 1/7 and halves the result, rounding up, minimum 1.
   Player discounts are then applied, also minimum 1. `skip_scaling` disables
   the random scaling and sale. Blood deals omit the level factor and add
   rarity-dependent surcharges; resource-specific blood-price overrides win.

7. **Reroll** -- `bodypart_reward.gd:69` and the shop reroll-machine script.
   A reward hashes its old seed with the reroll namespace and avoids its old
   resource. The machine rerolls descendant rewards and charges
   `4 * (times_used + 1)` before discount/minimum handling. The shop serializes
   `times_used`, so reload does not legitimately reset its price.

8. **Purchase, theft and persistence** -- `shop_item.gd:117`, `:206`, `:218`,
   `:229`; `RunSaveManager`'s shop save/apply functions.
   Vanilla purchases check affordability, debit money and hand off local rewards,
   with a refund while an editor pickup is pending. Finalization clears that
   refund and buy UI. Defeating the shopkeeper normally enables a separate free
   theft path. Run saves persist seeds/reward state, paid pedestals and reroll
   count, rather than generating a wholly new shop on load.

### Recovered evidence digests

These digests permit checking the exact privately recovered files used for the
main conclusions. They are not hashes of the encrypted/compiled resource bytes.

| Recovered resource | SHA-256 |
| --- | --- |
| `scn/environ/level_generator.gd` | `5490a8f3077cf56e41b23bea63d95654350aa3952763c126b3068d449cac2694` |
| `scn/environ/pickups/bodypart_reward.gd` | `3f62d7129f4609d6d61d1975f17ef32203ba2223e2b101e8c2a0355e920f8720` |
| `scn/utils.gd` | `c49422adb239d277c4719293e8181758d4cedad351ab2baafd82e25d19008793` |
| `scn/environ/pickups/shop_item.gd` | `83a0cec63b3cb782417306983dea147139c5dd639a7efbad565d532174b418e0` |

## Why the mod hooks purchases rather than replacing RNG

The original seeded reward and price generation stays intact. In each shop room
the client designates exactly one non-blood pedestal (first ordinary bodypart offer
by natural node-name order) and stores the choice as room metadata. The
`shop_item.gd` extension routes that pedestal's real `PickupArea.picked` signal,
`_take_for_free` theft path and `make_free` discount to the client. Other pedestals
call the vanilla methods. A fallback rewires the signal if the script takeover is
inactive. For the AP pedestal the client journals first, debits the price, marks
local rewards consumed/deleted, frees pickups, finalizes the pedestal, asks the
game to save and sends checks. Server acknowledgment is tracked separately and
missing acknowledgments retry. It never invokes the vanilla local-upgrade handoff
for an AP purchase.

The AP server owns item placement; the game does not roll a recipient.
Location IDs are 402938001 through 402948000. Research Grant is item 402939001.
The journal is keyed by seed/team/slot. Limitations: AP purchases are blocked
offline, killing the shopkeeper does not make the AP pedestal free, the campaign is
finite (vanilla after the last check), and the journal and run save are not one
atomic transaction (a crash between them can forgive a debit or lose grant coins).

## Executed verification

| Layer | Observed result | Does not establish |
| --- | --- | --- |
| Python tooling tests | 15 pass: guarded config/installer, reproducible archives and failure-publication checks | Actual interactive gameplay |
| Godot fixture suite | 53 assertions pass using production mod code and original game API doubles | Vanilla scene lifecycle correctness |
| AP 0.6.7 generation | Genuine two-player seed, 20 checks per player | Progression logic; this is filler-only |
| Genuine seed spoiler | Player 1 shipment 2 contains a Research Grant for player 2 | Every possible mixed-game placement |
| Live AP 0.6.7 MultiServer | Both clients authenticate; two purchases acknowledged; shipment 2 reaches player 2; redemption gives 15 coins; reconnect does not duplicate it | Actual vanilla debit/save implementation, because game state was doubled |
| Native demo smoke | `extended=true scene_extended=true client=true`, separate save directory | Entering a shop or playing a run |
| Steam integrity | Optional verification workflow implemented; verification skipped during executed build | Completed Steam verification |

The live test used seed `55899776043350644713`, generated with seed input
`20261017`; the server bound only to loopback and was stopped after testing.
The first live test timed out because it assumed an empty inventory receives a
`ReceivedItems` response. AP 0.6.7 sends neither initial nor Sync item history when
empty. Removing that incorrect readiness precondition made the actual purchase,
delivery, redemption and replay test pass; no production protocol change was needed.

Retained final native log:
[local-builds/demo-ap-28d4aj_8/native-smoke.log](local-builds/demo-ap-28d4aj_8/native-smoke.log).
Its successful marker does not erase the recorded headless engine/resource and
disabled-Sentry initialization errors.

The final end-to-end shell workflow completed successfully. Its transcript
(`final-build-install.log`) is retained locally, outside the repository.
The published launcher points to the verified private build above.

The genuine-server test was repeated successfully after the final installation.
Its transcript
(`final-live-test.log`) is retained locally, outside the repository.
It records `LIVE_AP_CROSS_PLAYER sender=1 check=402938002 recipient=2 bank=1`,
`LIVE_AP_RECONNECT replay_preserved=true`, and
`GODOT_TEST_RESULT live_archipelago=true failures=0`. This used disposable
game-state doubles and a fresh loopback server, which was stopped afterward;
it did not purchase checks in a user's campaign.

## Reported local purchase (October 17, 2026)

A purchase in the first published build produced a local upgrade and no check.
Observed: the MultiServer save, the client journal and `run_save.json` (run XGWA3CV8)
contained no AP purchase, and the Godot log had no purchase line (Godot `print`
output is buffered and was not a reliable record). The earlier design applied a
hidden eligibility filter per pedestal (ordinary bodypart, not choose-one, not
mixed), so a non-matching pedestal silently stayed vanilla and looked identical.
The exact pedestal bought cannot be reconstructed from the retained evidence.

The redesign makes the AP pedestal explicit and visible (blue ARCHIPELAGO tooltip
with the scouted item, recipient and game), forces one per shop, and writes a
flushed `client.log` line for every pick with its routing decision.
In the real engine (private app copy, headless) the actual `shop.tscn` and
`heart_shop.tscn` each designated only `Item1`, the real pick signal reached the
extension, logged `-> ARCHIPELAGO`, refused offline and granted no local reward.
The injected Settings tab (8th tab "Archipelago") and tooltip text were also
observed. Shop rooms cannot be added to the tree outside a run in release builds
(`shop_item._ready` reads a null `G.level_generator`), so those probes used
out-of-tree instances. An online paid purchase in a real run remains unverified.

## Full game port (app 3808690)

Investigated on October 17, 2026 against the locally installed macOS Steam
Pathogenic (`steam_data.json` app 3808690), project `config/git_describe="v1.2.1"`,
engine 4.7.2, Mod Loader 7.0.1. GDRE Tools privately recovered the hooked scripts
from both PCKs; recovered files are not included here.

| Official file | SHA-256 |
| --- | --- |
| `Contents/MacOS/Pathogenic` | `60a59e7c2f511368c66ed51bd74c0d7581a988a68399b404effb854b15fcb46f` |
| `Contents/Resources/Pathogenic.pck` | `dda98093c77d74290a0503fc8ff9d5b8a45370ed2c290a2db75bf8ce3ae99d9d` |

| Observation | Result |
| --- | --- |
| Demo vs. full scripts | `shop_item.gd`, `bodypart_reward.gd`, `pickup_area.gd`, `reward.gd`, `room.gd`, `item_room.gd`, `shop.gd`, `globals.gd`, `player.gd`, `options_menu.gd`, `run_save_manager.gd` and the Mod Loader core are byte-identical; `project.godot` differs only in app ID and `-dirty` |
| Why the demo cannot load mods | `mod_loader.gd` `_init` returns unless `steam/initialization/app_id == 3808690` |
| Workshop discovery on macOS | `get_game_install_dir` strips `Pathogenic.app/Contents/MacOS`, so Mod Loader scans `steamapps/workshop/content/3808690/<item>/*.zip` |
| Manifest contract | Required root keys and `extra.godot.authors/compatible_mod_loader_version/compatible_game_version` present; name/namespace match `^[A-Za-z0-9_]{3,}$` |
| Real-game headless smoke (`--mods-path` temp folder) | `ViMaSter-ArchipelagoShop.zip loaded`, `Installing script extension: res://scn/environ/pickups/shop_item.gd`, client logs `Archipelago is off`; no mod GDScript errors |
| Distribution | Game ships `GodotWorkshopUtility.app`; Workshop tags offered by `steam_data.json`: Organelles, Mutations, GUI, Cheats, Rooms, Enemies, Challenges, Cosmetic |

Not verified on the full game: an interactive run with a paid online shipment,
and loading from an actual Workshop subscription (no item exists yet).

## DeathLink verification

The installed full-game PCK still matches
`dda98093c77d74290a0503fc8ff9d5b8a45370ed2c290a2db75bf8ce3ae99d9d`.
Focused private GDRE 2.7.4 recovery confirmed `player.gd:380-431` exposes
`hit_no_signal`, its defense guards, and the synchronous `player_died` signal.
The native method performs HP damage, death effects, and run-end presentation.
`editor.gd` exposes `active` and the editor transition state. This is static
evidence, not a newly observed interactive death. Recovered source is not
included in this project.

| Recovered interface | SHA-256 |
| --- | --- |
| `scn/player/player.gd` | `976b57960b562152d4af1ccff846665e580c960f9ba99b152f5f2fcfb582f1cb` |
| `scn/signal_bus.gd` | `5c01f7299d2bf286528b8dcf3a08f7dfda23f5ff622b573846c88727908632c3` |

| Layer | Observed result | Limitation |
| --- | --- | --- |
| Python tooling | 25 tests pass, including reproducible builds using the tracked top-level mod source | No gameplay |
| Isolated Godot fixtures | 162 assertions pass; other games' payload variants (null/absent `cause`, numeric-string `time`, absent `source`) are accepted; incoming damage bypasses defenses, pause/editor closing defers damage, obsolete pending deaths are discarded, local deaths send once, received deaths do not echo, damage failures are explicit | Original API doubles, not native scenes |
| MultiworldGG 0.7.273 generation | Default-on and explicit on/off DeathLink settings reach exact slot data; source selection and 10,000-check boundary remain valid | Generated logic, not game execution |
| Real Dark Souls III client | Captured live DS3 bounce `{"time": 1792269493.0, "cause": null, "source": "Daniel"}`; the first build rejected it as malformed, which the tolerant parser fixes | In-game lethal damage from a DS3 death awaits one confirmation |
| Real MultiworldGG server | Three slots: two enabled and one disabled; local death sends a tagged event, the other enabled client takes lethal damage once, the disabled slot receives no DeathLink bounce, and reconnect restores subscription. Shipment delivery, grant replay protection, and persisted goal/checks still pass | Clients share one doubled game; test selects whose run/death it represents |

The live tests use an isolated runtime copy, generated seed, loopback-only server,
and temporary game data. No hosted room or installed game files are changed.
Server startup also logged an unrelated Oracle of Ages world import failure
because the local Python lacks Tkinter; Pathogenic generation and all live
assertions completed successfully.
An interactive death/animation/save transition in the full game remains
unverified; API-double and live-protocol tests do not establish that result.

## Requested references

- [Godot Modding: mod developer](https://wiki.godotmodding.com/#mod-developer):
  original-code mod distribution and Mod Loader conventions. No vanilla files
  are included in the distributable archives.
- [Decompiling games](https://wiki.godotmodding.com/guides/modding/tools/decompile_games/):
  GDRE-based local inspection and engine-version considerations.
- [Steam guide: Free Shop Rerolls](https://steamcommunity.com/sharedfiles/filedetails/?id=3770222119):
  the referenced page title was observable, but its implementation was not
  inspected. No claim of borrowing or verifying that mod's code.
- [Archipelago](https://archipelago.gg):
  custom-world generation and WebSocket multiworld protocol, additionally checked
  against a genuine 0.6.7 server in the live integration test.
