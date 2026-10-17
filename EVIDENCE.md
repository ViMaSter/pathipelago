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

The retained local REA export is
`$SESSION_FILES/evidence.json`.
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

The original seeded reward and price generation stays intact. The extension
intercepts eligible purchase/theft paths and substitutes the next AP check for
the local handoff. It journals first, debits the price, marks local rewards
consumed/deleted, finalizes the pedestal, asks the game to save and sends checks.
Server acknowledgment is tracked separately and missing acknowledgments retry.
It never invokes the vanilla local-upgrade handoff for an AP purchase.

The AP server owns item placement; the game does not roll a recipient.
Location IDs are 402938001 through 402938100. Research Grant is item 402939001.
The journal is keyed by seed/team/slot. See [README.md](README.md) for offline,
theft, finite-campaign and crash-consistency limitations.

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

The final end-to-end shell workflow completed successfully. Its transcript is
retained locally at
`$SESSION_FILES/final-build-install.log`.
The published launcher points to the verified private build above.

The genuine-server test was repeated successfully after the final installation.
Its retained transcript is
`$SESSION_FILES/final-live-test.log`.
It records `LIVE_AP_CROSS_PLAYER sender=1 check=402938002 recipient=2 bank=1`,
`LIVE_AP_RECONNECT replay_preserved=true`, and
`GODOT_TEST_RESULT live_archipelago=true failures=0`. This used disposable
game-state doubles and a fresh loopback server, which was stopped afterward;
it did not purchase checks in a user's campaign.

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
