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

`extra_checks` accepts 0-10000 and is the minimum randomized shipment count, raised to the number of
enabled unlocks when necessary (309 with every category enabled). Remaining
randomized slots contain "Research Grant", redeemed automatically for 15 coins
in the current or next MultiworldGG run. Natural-earn locations do not consume
randomized pool slots. The goal counts only randomized shipments. With every
category disabled, the campaign retains its Research Grant-only pool.
Setting it to zero with every remote category disabled produces no shipments;
the shipment goal is immediately complete.

## What does another world's item look like in Pathogenic?

Hovering the MultiworldGG pedestal replaces the upgrade description with the
scouted item, the recipient player, and the recipient's game.
