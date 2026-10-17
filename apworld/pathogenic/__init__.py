"""Original, finite shop-purchase campaign; no game assets or recovered source."""

from dataclasses import dataclass

from BaseClasses import Item, ItemClassification, Location, Region, Tutorial
from Options import (Accessibility, DefaultOnToggle, OptionError, PerGameCommonOptions,
                     ProgressionBalancing, Range, Visibility)
from worlds.AutoWorld import WebWorld, World


class ShopChecks(Range):
    """Number of shipments purchased across any number of runs. Rerolls add no checks."""

    display_name = "Shop Shipments"
    range_start = 1
    # Archipelago needs a fixed location table; this is its size, not a gameplay limit.
    range_end = 10000
    default = 20


class ShopUnlocks(DefaultOnToggle):
    """One pedestal in every coin shop is a Remote Unlock bought with coins."""

    display_name = "Remote Unlocks in Shops"


class ItemRoomUnlocks(DefaultOnToggle):
    """One free pedestal in every blue item room is a Remote Unlock."""

    display_name = "Remote Unlocks in Blue Item Rooms"


class BossRewardUnlocks(DefaultOnToggle):
    """One choice of every boss bodypart reward is a Remote Unlock."""

    display_name = "Remote Unlocks in Boss Rewards"


class LevelUpUnlocks(DefaultOnToggle):
    """The last card of every level-up mutation draft is a Remote Unlock."""

    display_name = "Remote Unlocks in Level-Up Drafts"


# Every Pathogenic location is always reachable and every item is filler, so
# these core options cannot change a seed; hide them from templates and the UI.
class HiddenProgressionBalancing(ProgressionBalancing):
    visibility = Visibility.none


class HiddenAccessibility(Accessibility):
    visibility = Visibility.none


@dataclass
class PathogenicOptions(PerGameCommonOptions):
    progression_balancing: HiddenProgressionBalancing
    accessibility: HiddenAccessibility
    shop_checks: ShopChecks
    shop_unlocks: ShopUnlocks
    item_room_unlocks: ItemRoomUnlocks
    boss_reward_unlocks: BossRewardUnlocks
    level_up_unlocks: LevelUpUnlocks


class PathogenicWeb(WebWorld):
    tutorials = [Tutorial(
        "Multiworld Setup Guide",
        "Subscribe to the Archipelago Shop Workshop mod and connect Pathogenic to a multiworld.",
        "English",
        "setup_en.md",
        "setup/en",
        ["ViMaSter"],
    )]


class PathogenicItem(Item):
    game = "Pathogenic"


class PathogenicLocation(Location):
    game = "Pathogenic"


class PathogenicWorld(World):
    """Reach shops and earn money through normal play; repeat runs as necessary."""

    game = "Pathogenic"
    web = PathogenicWeb()
    options_dataclass = PathogenicOptions
    options: PathogenicOptions
    required_client_version = (0, 6, 0)
    topology_present = False
    item_name_to_id = {"Research Grant": 402939001}
    location_name_to_id = {
        f"Shop Shipment {index:03d}": 402938000 + index
        for index in range(1, ShopChecks.range_end + 1)
    }

    def unlock_sources(self) -> dict:
        return {
            "shops": bool(self.options.shop_unlocks.value),
            "item_rooms": bool(self.options.item_room_unlocks.value),
            "boss_rewards": bool(self.options.boss_reward_unlocks.value),
            "level_ups": bool(self.options.level_up_unlocks.value),
        }

    def generate_early(self) -> None:
        if not any(self.unlock_sources().values()):
            raise OptionError(
                f"{self.player_name}: enable at least one Remote Unlock source "
                "(shop_unlocks, item_room_unlocks, boss_reward_unlocks or level_up_unlocks)."
            )

    def create_regions(self) -> None:
        menu = Region("Menu", self.player, self.multiworld)
        campaign = Region("Shop Campaign", self.player, self.multiworld)
        self.multiworld.regions.extend([menu, campaign])
        menu.connect(campaign)
        for index in range(1, self.options.shop_checks.value + 1):
            name = f"Shop Shipment {index:03d}"
            campaign.locations.append(
                PathogenicLocation(self.player, name, self.location_name_to_id[name], campaign)
            )
        self.multiworld.completion_condition[self.player] = lambda state: all(
            state.can_reach_location(f"Shop Shipment {index:03d}", self.player)
            for index in range(1, self.options.shop_checks.value + 1)
        )

    def create_items(self) -> None:
        self.multiworld.itempool.extend(
            self.create_item("Research Grant")
            for _ in range(self.options.shop_checks.value)
        )

    def create_item(self, name: str) -> PathogenicItem:
        return PathogenicItem(
            name, ItemClassification.filler, self.item_name_to_id[name], self.player
        )

    def get_filler_item_name(self) -> str:
        return "Research Grant"

    def fill_slot_data(self) -> dict:
        return {
            "schema": 2,
            "shop_checks": self.options.shop_checks.value,
            "sources": self.unlock_sources(),
        }
