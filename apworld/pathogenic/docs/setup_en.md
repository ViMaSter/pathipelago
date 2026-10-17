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
Source and releases: https://github.com/ViMaSter/pathipelago

## Generation and hosting

Pathogenic is a custom APWorld, not a bundled game on multiworld.gg. Install
`pathogenic.apworld` in the latest stable MultiworldGG desktop generator (or use
the source-generation helpers in the repository) and generate locally with all
players' YAML files. Upload only the generated `AP_<seed>.zip` to
https://multiworld.gg/uploads and create a room.

Custom-world lobbies can collect files, but require downloading the package for
local generation. Browser-only generation is not supported for Pathogenic.
The room's generic tracker is supported; there is no dedicated Pathogenic tracker,
DeathLink, in-game text client, or admin interface. Use https://chat.multiworld.gg
for text commands. macOS support for other games depends on their own clients and
libraries.

The Godot transport does not negotiate WebSocket compression. MultiworldGG
0.7.273 accepts uncompressed connections but warns that they may be unsupported
in a future release. Exact-version-only servers are also outside the default
supported connection policy.

The renamed mod does not migrate or delete older Archipelago settings/saves.
Remove any old local `ViMaSter-ArchipelagoShop` mod copy before installing
`ViMaSter-MultiworldGGShop`, so both do not load together.
