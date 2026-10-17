# Pathogenic: MultiworldGG Shop

[Subscribe on Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3821496115)

Send items to other players through shops, item rooms, boss rewards, and level-ups.
Received Research Grants give 15 coins. Progress carries over between runs.

## Setup

1. Subscribe on [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3821496115) and start Pathogenic.
2. Open **Settings > MultiworldGG**.
3. Enter the room's WebSocket address (`ws://host:port` or `wss://host:port`), slot name, and password if needed.
4. Turn on **Enable MultiworldGG for new runs** and click **Connect**.
5. Start a **new run**.

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
  shop_checks: 20             # 1-10000 checks across all runs
  shop_unlocks: false         # coin shops
  item_room_unlocks: true     # blue item rooms
  boss_reward_unlocks: false  # boss rewards
  level_up_unlocks: false     # level-up drafts
  death_link: true            # share deaths with other DeathLink games (default true)
```

Keep at least one source enabled.

DeathLink works in both directions: deaths in other participating games deal
guaranteed lethal damage to your current MultiworldGG run, and your deaths are
sent to them. While paused or editing upgrades, the hit waits until gameplay
resumes in that same run. Deaths outside a living MultiworldGG run are ignored,
and deaths are not replayed after reconnecting. Vanilla runs are unaffected.
Set `death_link: false` before generating to disable it. Older seeds without
this option keep DeathLink off; regenerate with the updated APWorld to enable it.
