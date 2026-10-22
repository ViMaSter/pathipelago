# Pathogenic Setup Guide

1. Own Pathogenic on Steam (the demo does not load mods) and subscribe to the
   MultiworldGG Shop mod on the Pathogenic Steam Workshop.
2. Start the game through Steam.
3. Open Settings > MultiworldGG, turn on "Enable MultiworldGG for new runs", enter the
   WebSocket server address from your multiworld.gg room page, your case-sensitive
   slot name, and the room password if any, then press Connect. Use the assigned
   port, not a fixed default or the HTTPS room-page URL.
4. Start a new run. Buy or pick the pedestal marked MULTIWORLDGG to send a Shop Shipment.

The client log is shown on the same settings tab and stored in the game's user folder
under `multiworldgg_shop/client.log` (macOS:
`~/Library/Application Support/Godot/app_userdata/Pathogenic/multiworldgg_shop/client.log`).
Source and releases: https://github.com/mahnkepelago/pathogenic

## Generation and hosting

Pathogenic is a custom APWorld, not a bundled game on multiworld.gg. Install
`pathogenic.apworld` in the latest stable MultiworldGG desktop generator (or use
the source-generation helpers in the repository) and generate locally with all
players' YAML files. Upload only the generated `AP_<seed>.zip` to
https://multiworld.gg/uploads and create a room.

Custom-world lobbies can collect files, but require downloading the package for
local generation. Browser-only generation is not supported for Pathogenic.
The five `remote_*` category toggles default to true. Each enabled non-plasmid
unlock and each of the 36 shared plasmid slots gets a shipment, then `coin_checks`, `dna_checks`, and `plasmid_fragment_checks` add that
many Coins, DNA, and Plasmid Fragments filler items (0-10000 each). Set the
corresponding `*_amount` to configure each reward (1-10000). Optional natural-earn
self-rewards are additional locations, not randomized shipment slots or goal
requirements. Disable all five categories to create a currency-only seed.
The room's generic tracker is supported; there is no dedicated Pathogenic tracker,
in-game text client, or admin interface. Use https://chat.multiworld.gg
for text commands. macOS support for other games depends on their own clients and
libraries.

## DeathLink

`death_link: true` is the default YAML setting. DeathLink shares deaths in both
directions with other participating games. Received deaths deal guaranteed lethal
damage to your current MultiworldGG run, bypassing armor, invulnerability,
damage blocking, and damage reduction for that hit only.

If paused or editing upgrades, the hit waits until gameplay resumes in the same
run. Deaths received without a living active MultiworldGG run are ignored;
they never carry into the next run. Vanilla runs are unaffected, incoming deaths
are not echoed, and deaths while disconnected are not replayed on reconnect.

Set `death_link: false` in your YAML before generation to disable both directions.
There is no separate local DeathLink toggle. Existing seeds without this slot
option leave it off; regenerate with the updated APWorld to enable it.

The Godot transport does not negotiate WebSocket compression. MultiworldGG
0.7.273 accepts uncompressed connections but warns that they may be unsupported
in a future release. Exact-version-only servers are also outside the default
supported connection policy.

The renamed mod does not migrate or delete older Archipelago settings/saves.
Remove any old local `ViMaSter-ArchipelagoShop` mod copy before installing
`ViMaSter-MultiworldGGShop`, so both do not load together.

## Catalogue maintenance (developers)

`catalog.json` contains factual metadata only; recovered game assets and scripts
must not be distributed. Regenerate from an explicitly supplied private v1.2.1
resource tree:

```sh
python3 tools/extract_unlock_catalog.py --recovered /absolute/private/resource-root
python3 tools/extract_unlock_catalog.py --recovered /absolute/private/resource-root --check
python3 -m unittest discover -s tests -p test_catalog.py
```

The root must contain `translations/translations.csv` and the recovered `scn`
resource hierarchy. No game scripts are executed. Existing output is the ID
ledger: keys retain their IDs, new keys append, and vanished keys or unresolved
references/translations fail instead of silently disappearing. Keep the committed
catalogue when regenerating. Optional `--output` selects a different ledger/output.
The audited unused standalone plasmids `plasmid:global:strafer` and
`plasmid:global:worm` are explicitly retired; IDs 309 and 310 remain reserved and
are never reused. All other disappeared keys still fail closed.
Set `PATHOGENIC_RECOVERED` to the private root to include full regeneration in
the unit tests; otherwise only that private-data test is skipped.

The exact catalogue envelope is `{"schema": 1, "entries": [...]}`. Every entry
has integer `id`, stable `key`, `kind`, unique AP item `name`, and integer
`parasite` (`-1` means global). Native gated entries additionally expose canonical
Godot `condition` identity (`res://...tres::SubResourceID`), `resource`, `stat`,
numeric `threshold`, `comparison` (`>=`, `<=`, `truthy`), `global`, and
`requires_full_game`. Loadout entries also identify their `bodypart`.
Plasmids expose nonempty `map`, `node`, `scene`, `section`, `save_key`, and a
positive integer `slot`: the plasmid's rank on its map by breadth-first distance
from the starting node, ties broken by node name. Slots are unique per parasite.
All 216 shipped entries use `section: "plasmids<parasite>"` and `save_key`
equal to `node`; their required string field `condition` is `""` (no native
gate). Catalogue IDs are nonnegative integers: ID 0 is valid and must not be
rejected or renumbered. Starting nodes and
unreferenced standalone scenes are omitted. Extraction verifies connectivity
from each map's starting node; this is static acquisition-path evidence, not
an observed in-game purchase. Environment entries also expose their internal
`environment` name.

**Target identity is not gate identity.** Exactly one native condition is shared:
`res://scn/metaprogression/loadouts/loadout_collector.tres::Resource_kwm52`
belongs to both ID 35 (Chromatophore Gland) and ID 38 (Chromatophore Lens).
These are intentionally separate AP targets. Remote grants must be keyed by
catalogue ID/resource, not solely by `condition`; overriding that shared
UnlockCondition alone grants both targets. Natural condition satisfaction
correctly earns both. Never rewrite the factual condition path to invent
independent native resources.

Representative runtime identities (all paths below are literal catalogue values):

```json
{"id":0,"kind":"character","parasite":5,"resource":"res://scn/metaprogression/unlocks/parasite_unlocks/parasite_unlocks.tres::Resource_parasite_amoeba","condition":"res://scn/metaprogression/unlocks/parasite_unlocks/parasite_unlocks.tres::Resource_unlock_amoeba"}
{"id":5,"kind":"environment","parasite":-1,"resource":"res://scn/metaprogression/unlocks/environmental_unlocks/antibiotics_unlock.tres","condition":"res://scn/metaprogression/unlocks/environmental_unlocks/antibiotics_unlock.tres::Resource_antibiotics_uc","environment":"antibiotics"}
{"id":11,"kind":"loadout","parasite":5,"resource":"res://scn/metaprogression/loadouts/loadout_amoeba.tres::Resource_34poi","condition":"res://scn/metaprogression/loadouts/loadout_amoeba.tres::Resource_remq2","bodypart":"res://scn/player/bodyparts/internal/backstab.tres"}
{"id":79,"kind":"organelle","parasite":-1,"resource":"res://scn/player/bodyparts/external/electric_harpoon.tres","condition":"res://scn/player/bodyparts/external/electric_harpoon.tres::Resource_7fst3"}
{"id":92,"kind":"plasmid","parasite":0,"map":"res://scn/metaprogression/plasmids/plasmid_map.tscn","node":"AttackSpeedPlasmid","scene":"res://scn/metaprogression/plasmids/all/starting_mutation_plasmid.tscn","section":"plasmids0","save_key":"AttackSpeedPlasmid","slot":17}
```

These are field projections, not complete entries. `key` is `kind:resource` for
native-gated entries and `plasmid:<parasite>:<node>` for plasmids. The scene name
`starting_mutation_plasmid.tscn` does not mean the excluded `StartingPlasmid`;
ID 92 is an ordinary purchasable map node. Repeated effects are retained under
their distinct node keys. All 14 gated organelles are present in the shipped
`all_bodyparts.tres` resource group's pool; the private-data test checks this.

Catalogue `organelle` and `environment` entries are retired from generation in
slot schema 6: their IDs stay reserved and are still honoured for schema 1-5
seeds, but new seeds never contain them and schema 6 slot data that selects one
is rejected. In a schema 6 campaign every bodypart drop gate under
`res://scn/player/bodyparts/` is open.

Organelle deliveries use the separate pool `organelles.json`
(`{"schema": 1, "entries": [{"key", "resource", "name", "id"}], "retired": {}}`),
regenerated with `python3 tools/extract_organelle_pool.py --recovered <root>`
(`--check` verifies it). It lists every non-disabled `external/` and `internal/`
bodypart in `all_bodyparts.tres` (89 in v1.3.6; every character draws from this
same pool). IDs are stable per `key` and never reused. Item
`Organelle: <name>` has ID `402980000 + id`. Received organelles are queued in the
campaign journal (`organelles_delivered` counts completed deliveries) and each
opens `G.editor.show_editor(bodypart)` when the player is in control.

AP item IDs of non-plasmid entries are `402960000 + id`; optional
natural-location IDs are `402970000 + id`, named `Earn <item name>`. Plasmids
have no per-entry items or locations: `Plasmid Slot NN` items are
`402960000 + 30000 + N` and `Earn Plasmid Slot NN` locations are
`402970000 + 30000 + N` (N = 1-36). Slot locations hold randomized items. Currency item IDs are Coins
(`402939001`), DNA (`402939002`), and Plasmid Fragments (`402939003`);
existing shipment IDs (`402938000 + shipment index`) do not change. The old
Research Grant name at ID `402939001` remains accepted by existing seeds.
The module exports `CATALOG_SCHEMA`, `CATALOG_ENTRIES`, `CATALOG_BY_ID`,
`CATALOG_BY_KEY`, `UNLOCK_ITEM_BASE`, `NATURAL_LOCATION_BASE`, `UNLOCK_ITEM_IDS`,
`NATURAL_LOCATION_IDS`, `PLASMID_SLOT_BASE`, `PLASMID_SLOTS`,
`PLASMID_SLOT_ITEM_IDS`, `PLASMID_SLOT_LOCATION_IDS`, `natural_location_name(entry)`
and `plasmid_slot_name(slot)`.

Slot data is exactly:

```json
{
  "schema": 6,
  "catalog_schema": 1,
  "organelle_pool_schema": 1,
  "organelle_ids": [1, 2],
  "start_with_all_characters": false,
  "unlock_ids": [0, 1],
  "checks": 4,
  "coin_amount": 15,
  "dna_amount": 1,
  "plasmid_fragment_amount": 1,
  "sources": {
    "shops": true,
    "item_rooms": true,
    "boss_rewards": true,
    "level_ups": true
  },
  "death_link": true,
  "required_victories": 0
}
```

The example selects two catalogue IDs and two organelle deliveries. Actual `unlock_ids` enumerate every
enabled entry (including plasmids) in stable ID order; the client maps enabled
plasmids to their slots. `checks` is the total randomized shipment count,
including enabled character and loadout unlocks, plasmid slots, organelle
deliveries (`organelle_ids` is empty when `remote_organelles` is off) and all
configured currency checks. Static item/location name maps contain the entire catalogue and all slots
regardless of enabled categories. Schema 5 slot data (catalogue organelle-drop and environment items), schema 4
slot data (per-character plasmid items)
and schema 1/2/3 slot data remain supported; `extra_checks` is read as the older total check
count, and legacy Research Grant items still award 15 Coins.
