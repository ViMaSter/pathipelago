"""Original, finite shop-purchase campaign; no game assets or recovered source."""

from dataclasses import dataclass

from BaseClasses import Item, ItemClassification, Location, Region, Tutorial
from Options import PerGameCommonOptions, Range
from worlds.AutoWorld import WebWorld, World


class ShopChecks(Range):
    """Number of shipments purchased across any number of runs. Rerolls add no checks."""

    display_name = "Shop Shipments"
    range_start = 5
    range_end = 100
    default = 20


@dataclass
class PathogenicOptions(PerGameCommonOptions):
    shop_checks: ShopChecks


class PathogenicWeb(WebWorld):
    tutorials = [Tutorial(
        "Multiworld Setup Guide",
        "Install the local Archipelago shop mod and connect Pathogenic Demo to a multiworld.",
        "English",
        "setup_en.md",
        "setup/en",
        ["Local Archipelago Shop"],
    )]


class PathogenicItem(Item):
    game = "Pathogenic Demo"


class PathogenicLocation(Location):
    game = "Pathogenic Demo"


class PathogenicWorld(World):
    """Reach shops and earn money through normal play; repeat runs as necessary."""

    game = "Pathogenic Demo"
    web = PathogenicWeb()
    options_dataclass = PathogenicOptions
    options: PathogenicOptions
    required_client_version = (0, 6, 0)
    topology_present = False
    item_name_to_id = {"Research Grant": 402939001}
    location_name_to_id = {
        f"Shop Shipment {index:03d}": 402938000 + index
        for index in range(1, 101)
    }

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
        return {"schema": 1, "shop_checks": self.options.shop_checks.value}
