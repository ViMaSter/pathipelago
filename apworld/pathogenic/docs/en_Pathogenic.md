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

"Research Grant", which is redeemed automatically for 15 coins in the current
(or next) MultiworldGG run.

## What does another world's item look like in Pathogenic?

Hovering the MultiworldGG pedestal replaces the upgrade description with the
scouted item, the recipient player, and the recipient's game.
