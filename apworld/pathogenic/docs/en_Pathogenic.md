# Pathogenic

## What does randomization do to this game?

Every enabled source contains one MultiworldGG pedestal or card. The sources are shop rooms
(`shop_unlocks`), blue item rooms (`item_room_unlocks`), boss bodypart selections
(`boss_reward_unlocks`) and level-up mutation drafts (`level_up_unlocks`). All are on by default, and at
least one must stay on. The remote unlock is
shown as an Enhancer icon named "Remote Unlock n/N". Buying it with in-game coins
(or taking it for free in an item room, after a boss, or as the last level-up card) sends the next "Shop Shipment" location
to the multiworld instead of granting an upgrade. All other pedestals stay vanilla.

The mod is off by default. Enable it in Settings > MultiworldGG before starting a run.
Each run keeps the mode it started with: turning the setting on mid-run does not
add remote unlocks, and turning it off or disconnecting does not remove them.

## Does this game support DeathLink?

Yes, in both directions. The YAML option `death_link` defaults to `true`.
Other participating games' deaths deal lethal damage to the current
MultiworldGG run, bypassing defenses for that hit, and Pathogenic deaths are sent
to those games. Pausing or editing upgrades defers the hit until gameplay resumes
in that same run. Deaths with no living active MultiworldGG run are ignored, never
queued for the next run. Incoming deaths are not echoed and disconnected deaths
are not replayed. Vanilla runs are unaffected.

Generate with `death_link: false` to disable it. Older seeds without the option
keep DeathLink off and must be regenerated to enable it.

## What items can appear in other players' worlds?

Character, plasmid, starting-loadout, organelle and environmental unlocks are
included by default. They are **additive**: receiving one grants it remotely,
but its normal acquisition remains available. A starting-loadout option and its
organelle's random-drop unlock are separate items with separate native gates.
Repeated same-named plasmid effects are distinct character-specific map nodes;
starting plasmids are excluded.

The v1.2.1 catalogue contains 309 entries: 5 characters, 216 plasmids, 68 loadout
options, 14 organelles and 6 environmental features. Plasmids are connected nodes
in the seven active maps. Two unreferenced standalone character-unlock scenes
are excluded because they cannot be naturally acquired through those maps.

Use `remote_characters`, `remote_plasmids`, `remote_loadouts`, `remote_organelles`
and `remote_environment` to disable individual categories. Every selected unlock
appears once in the randomized shipment pool and has an additional optional
`Earn ...` location containing a fixed copy for the same player. Native feats are
never required by generation logic or the goal. Unlock items are useful, not
progression.

Set `start_with_all_characters: true` to start the isolated campaign with the full
roster unlocked. It defaults to false. When enabled, `remote_characters` is ignored:
the five character items, their randomized shipments and their optional Earn checks
are all omitted, so other players cannot receive no-op character rewards for you.
Other unlock categories are unchanged. This requires the updated client and a newly
generated seed; it does not change existing rooms or vanilla profiles.

`coin_checks`, `dna_checks`, and `plasmid_fragment_checks` each add 0-10000
filler shipment checks. Their corresponding `*_amount` settings (1-10000)
control how much Coins, DNA, or Plasmid Fragments each item awards. The generator
creates one shipment per enabled unlock, plus exactly the configured filler
checks. Natural-earn locations do not consume randomized pool slots. The goal
counts randomized shipments plus `required_victories` MultiworldGG-run wins (0-50, default 0).
With every category and filler count disabled, there are no shipments and the goal is immediately complete
only when `required_victories` is 0. Victories persist across runs and reconnects; continuing a won run
does not count it again. Vanilla and daily runs do not count. Optional natural-earn locations remain optional.

Currency rewards wait in the journal until a living MultiworldGG run is ready;
Coins and DNA are added to that run, while Plasmid Fragments use the campaign's
isolated progression profile. Older schema 1/2/3 seeds remain compatible:
Research Grant item ID 402939001 still awards 15 coins.

## What does another world's item look like in Pathogenic?

Hovering the MultiworldGG pedestal replaces the upgrade description with the
scouted item, the recipient player, and the recipient's game.
