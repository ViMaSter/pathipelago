# Pathogenic: Archipelago Shop

[Archipelago](https://archipelago.gg) multiworld mod for [Pathogenic](https://store.steampowered.com/app/3808690/).
One pedestal in shops, blue item rooms, boss rewards and level-up drafts becomes a
**Remote Unlock** that sends a check to another player's game. Received Research Grants
pay out 15 coins each. Off by default; runs started with it off stay vanilla.

- [Steam Workshop item](https://steamcommunity.com/sharedfiles/filedetails/?id=3821496115)
- [`pathogenic.apworld` (releases)](https://github.com/ViMaSter/pathipelago/releases/latest)

## Versions

- Pathogenic 1.2.1 (Steam app 3808690)
  - Godot 4.7.2
  - Mod Loader 7.0.1
- Archipelago 0.6.7 or newer (tested with 0.6.7 and 0.6.8)

## Screenshots

![Start screen with Archipelago enabled](docs/screenshots/0_Start.png)

![Remote Unlock in a blue item room](docs/screenshots/1_Unlocks.png)

![Settings > Archipelago](docs/screenshots/2_Settings.png)

## Player options

[Pathogenic.yaml](Pathogenic.yaml):

```yaml
name: Pathogenic{number}   # slot name; {number} becomes 1, 2, ... (Pathogenic1)
game: Pathogenic
description: Persistent numbered remote unlocks across repeatable runs.
Pathogenic:
  progression_balancing: 50  # ignored: every location is always reachable
  accessibility: full        # ignored: the world has only filler items
  # Total Remote Unlock checks across all runs (5-100, default 20).
  shop_checks: 20
  # Where Remote Unlocks appear (default: all true). At least one must be true;
  # a disabled source stays completely vanilla.
  shop_unlocks: false        # one coin pedestal in every shop
  item_room_unlocks: true    # one free pedestal in every blue item room
  boss_reward_unlocks: false # one choice of every boss bodypart reward
  level_up_unlocks: false    # last card of every level-up mutation draft
```

## Example: Running Pokémon Red and Pathogenic

Put these files in one folder:

| File | Get it from |
| --- | --- |
| `PkmnPlayer.yaml` | [Pokémon Red and Blue options page](https://archipelago.gg/games/Pokemon%20Red%20and%20Blue/player-options) with player name `PkmnPlayer` (or use [example/PkmnPlayer.yaml](example/PkmnPlayer.yaml)) |
| `Pathogenic.yaml` | [Pathogenic.yaml](Pathogenic.yaml) from this repository (Pathogenic is a custom game, so archipelago.gg has no options page for it) |
| `pathogenic.apworld` | [Releases](https://github.com/ViMaSter/pathipelago/releases/latest) |
| `generate.sh` | [example/generate.sh](example/generate.sh) |

1. Run `./generate.sh` in that folder. It needs Python 3.11 to 3.13, downloads Archipelago
   once and writes `output/AP_<seed>.zip`. Custom games can't be generated on
   archipelago.gg, which is why this step runs locally.
2. Upload `output/AP_<seed>.zip` at [archipelago.gg/uploads](https://archipelago.gg/uploads)
   and create a room.
3. Pokémon: download the patch from the room page and
   [apply it](https://archipelago.gg/tutorial/Pokemon%20Red%20and%20Blue/setup_en), then
   connect as `PkmnPlayer`.
4. Pathogenic: subscribe to the [Workshop item](https://steamcommunity.com/sharedfiles/filedetails/?id=3821496115),
   start the game and open **Settings > Archipelago**.
5. Turn on **Enable Archipelago for new runs**, set **Server** to `ws://archipelago.gg:<port>`
   (the port from the room's `/connect archipelago.gg:<port>`), **Slot** to `Pathogenic1`, then
   click **Connect**.
6. Start a **new** run.
