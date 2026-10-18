# Pathogenic: MultiworldGG Shop

[Subscribe on Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3821496115)

Send items to other players through shops, item rooms, boss rewards, and level-ups.
Coins, DNA, and Plasmid Fragments can fill additional checks, with amounts set in the YAML.
Currency rewards wait for a living campaign run and progress carries over between runs.
Version 0.2 also receives permanent character, Plasmid, starting-loadout,
organelle-drop, and environment unlocks in a separate server-bound campaign.

## Setup

1. Subscribe on [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3821496115) and start Pathogenic.
2. Open **Settings > MultiworldGG**.
3. Enter the room's WebSocket address (`ws://host:port` or `wss://host:port`), slot name, and password if needed.
4. Turn on **Enable MultiworldGG for new runs** and click **Connect**.
5. On the first launch after installing this version, restart Pathogenic once
   when Mod Loader requests it. Progression hooks require that restart; campaign
   starts remain blocked until they are active.
6. Wait for the campaign to connect and synchronize, then start or continue its run.

## Generate a room

1. Get `pathogenic.apworld` through the [Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3821496115).
2. Install it in the [MultiworldGG generator](https://multiworld.gg/downloads).
3. Add [Pathogenic.yaml](Pathogenic.yaml) and the other players' YAML files, then generate locally.
4. Upload the generated ZIP to [multiworld.gg](https://multiworld.gg/uploads) and create a room.
5. Share the room page and use its assigned server address and port.

Alternatively, put the APWorld, YAML files, [generate.sh](example/generate.sh),
and [generate.py](example/generate.py) in one folder and run `bash generate.sh`.
Requires Python 3.13.5+ below 3.14, or 3.12.7+ below 3.13.

## Options

```yaml
name: Pathogenic{number}
game: Pathogenic
Pathogenic:
  progression_balancing: 50  # ignored: every location is always reachable
  accessibility: full        # ignored: native feats are optional, never logic gates
  
  death_link: true            # share deaths with other DeathLink games (default true)

  coin_checks: 20               # additional filler checks for Coins (0-10000)
  coin_amount: 15               # coins per Coins item (1-10000)
  dna_checks: 0                  # additional filler checks for DNA (0-10000)
  dna_amount: 1                  # DNA per DNA item (1-10000)
  plasmid_fragment_checks: 0     # additional filler checks for Plasmid Fragments (0-10000)
  plasmid_fragment_amount: 1     # fragments per item (1-10000)
  
  # where you can unlock things
  shop_unlocks: false         # coin shops
  item_room_unlocks: true     # blue item rooms
  boss_reward_unlocks: false  # boss rewards
  level_up_unlocks: false     # level-up drafts

  # things other people can unlock
  remote_characters: true
  remote_plasmids: true
  remote_loadouts: true
  remote_organelles: true
  remote_environment: true

  required_victories: 0        # wins needed in addition to sending every randomized shipment (0-50)
```

Keep at least one source enabled.

The goal is to send every randomized shipment and win `required_victories` MultiworldGG runs (default 0).
Victories persist across runs and reconnects; continuing or replaying a victory callback does not count it twice.
Vanilla and daily runs do not count.

## Permanent unlocks and natural acquisition

The installed v1.2.1 catalogue contains **309 unlocks**: 5 characters, 216
character-specific Plasmid nodes, 68 starting-loadout options, 14 organelle-drop
gates, and 6 environment features. Repeated Plasmid effects on different maps
are separate items. A starting-loadout unlock is distinct from that organelle's
random-drop gate.

All five remote categories default on. The generator creates one shipment for each
enabled unlock (309 with every category enabled) plus the configured currency checks.
Each filler item awards its configured Coins, DNA, or Plasmid Fragments amount.
Disable categories before generation to keep their ordinary in-campaign acquisition
behavior. With all remote categories disabled and all currency checks set to zero,
there are no shipments and the goal is immediately complete if `required_victories` is 0.

Each selected unlock also has an optional **Earn ...** location with a fixed
matching self-reward. Either satisfy the original requirement in your campaign
or receive the item from another player: both routes unlock the same content.
Native feats submit checks and wait for server confirmation; remote items never
fabricate achievement statistics. Optional Earn locations do not count toward
the goal, so difficult feats are not required to finish the multiworld.

Server-owned Plasmid nodes can be assigned/unassigned without paying again.
Map adjacency and connectivity still apply. They do not refund generic respec
points or require buying a native cap increase. Buying an unowned node normally
remains a natural acquisition route.

Regenerate with the bundled APWorld to obtain the new item pool. Older schema
1/2/3 seeds remain compatible: their Research Grant item (ID 402939001) still
awards 15 coins. Upgrading does not add items to an existing seed.

## Save isolation

Enabling MultiworldGG in the menu selects an isolated staging profile before
native saves load. After server synchronization, a separate profile is selected
by **seed + team + slot**, with a full identity marker to reject mismatches.
Rehosting the same seed/slot resumes that campaign; a different seed or slot
does not share its progression.

Normal profiles, legacy saves, their active-profile pointer, run saves, and
keybind files are not imported, cleared, or used by the campaign. Only
server-received items and server-confirmed native unlock checks confer selected
entitlements. Native attempts, run state, currency, and Plasmid assignments are
saved inside the campaign profile, not in a normal profile. Steam achievement
imports, achievement awards, and leaderboard uploads are suppressed there.

Start/Continue require a synchronized server connection. Disconnecting keeps the
campaign selected rather than falling back to a normal save. Return to the menu
and disable MultiworldGG to disconnect and restore normal profile routing.
Toggling during a run applies at the next menu; it never moves a running game
between profiles. Daily runs are unavailable while MultiworldGG is enabled,
because their automatic unlock bypass would not follow server entitlements.
Configuration, identity, or journal errors block play rather than resetting data
or opening a normal save.

DeathLink works in both directions: deaths in other participating games deal
guaranteed lethal damage to your current MultiworldGG run, and your deaths are
sent to them. While paused or editing upgrades, the hit waits until gameplay
resumes in that same run. Deaths outside a living MultiworldGG run are ignored,
and deaths are not replayed after reconnecting. Vanilla runs are unaffected.
Set `death_link: false` before generating to disable it. Older seeds without
this option keep DeathLink off; regenerate with the updated APWorld to enable it.
