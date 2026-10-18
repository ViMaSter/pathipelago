"""Finite remote shipments and additive unlocks; no game assets or source."""

from dataclasses import dataclass
import json
from pkgutil import get_data

from BaseClasses import Item, ItemClassification, Location, Region, Tutorial
from Options import (Accessibility, DeathLink, DefaultOnToggle, OptionError, PerGameCommonOptions,
                     ProgressionBalancing, Range, Visibility)
from worlds.AutoWorld import WebWorld, World


CATALOG_SCHEMA = 1
UNLOCK_ITEM_BASE = 402960000
NATURAL_LOCATION_BASE = 402970000
CATALOG = json.loads(get_data(__name__, "catalog.json").decode("utf-8"))
if CATALOG["schema"] != CATALOG_SCHEMA:
    raise ValueError("Unsupported Pathogenic unlock catalogue")
CATALOG_ENTRIES = tuple(CATALOG["entries"])
CATALOG_BY_ID = {entry["id"]: entry for entry in CATALOG_ENTRIES}
CATALOG_BY_KEY = {entry["key"]: entry for entry in CATALOG_ENTRIES}
CATEGORY_OPTIONS = {
    "character": "remote_characters",
    "plasmid": "remote_plasmids",
    "loadout": "remote_loadouts",
    "organelle": "remote_organelles",
    "environment": "remote_environment",
}


def natural_location_name(entry: dict) -> str:
    return f"Earn {entry['name']}"


UNLOCK_ITEM_IDS = {entry["name"]: UNLOCK_ITEM_BASE + entry["id"] for entry in CATALOG_ENTRIES}
NATURAL_LOCATION_IDS = {
    natural_location_name(entry): NATURAL_LOCATION_BASE + entry["id"]
    for entry in CATALOG_ENTRIES
}
COINS = "Coins"
DNA = "DNA"
PLASMID_FRAGMENTS = "Plasmid Fragments"
FILLER_ITEM_IDS = {
    COINS: 402939001,
    DNA: 402939002,
    PLASMID_FRAGMENTS: 402939003,
}
MAX_FILLER_CHECKS = 10_000
MAX_SHIPMENTS = len(CATALOG_ENTRIES) + len(FILLER_ITEM_IDS) * MAX_FILLER_CHECKS


class CoinChecks(Range):
    """Additional randomized shipment checks filled with Coins."""

    display_name = "Coin Checks"
    range_start = 0
    range_end = MAX_FILLER_CHECKS
    default = 0


class CoinAmount(Range):
    """Coins awarded by each Coins item."""

    display_name = "Coin Amount"
    range_start = 1
    range_end = 10_000
    default = 15


class DNAChecks(Range):
    """Additional randomized shipment checks filled with DNA."""

    display_name = "DNA Checks"
    range_start = 0
    range_end = MAX_FILLER_CHECKS
    default = 0


class DNAAmount(Range):
    """DNA awarded by each DNA item."""

    display_name = "DNA Amount"
    range_start = 1
    range_end = 10_000
    default = 1


class PlasmidFragmentChecks(Range):
    """Additional randomized shipment checks filled with Plasmid Fragments."""

    display_name = "Plasmid Fragment Checks"
    range_start = 0
    range_end = MAX_FILLER_CHECKS
    default = 0


class PlasmidFragmentAmount(Range):
    """Plasmid Fragments awarded by each Plasmid Fragments item."""

    display_name = "Plasmid Fragment Amount"
    range_start = 1
    range_end = 10_000
    default = 1


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


class RemoteCharacters(DefaultOnToggle):
    """Include character unlocks; normal character acquisition remains available."""

    display_name = "Remote Character Unlocks"


class RemotePlasmids(DefaultOnToggle):
    """Include individual character-specific plasmid nodes, not starting nodes."""

    display_name = "Remote Plasmid Unlocks"


class RemoteLoadouts(DefaultOnToggle):
    """Include gated starting-loadout choices, using their own native gates."""

    display_name = "Remote Loadout Unlocks"


class RemoteOrganelles(DefaultOnToggle):
    """Include gated organelle random-drop unlocks, separate from loadout choices."""

    display_name = "Remote Organelle Unlocks"


class RemoteEnvironment(DefaultOnToggle):
    """Include environmental feature unlocks without replacing normal acquisition."""

    display_name = "Remote Environment Unlocks"


class PathogenicDeathLink(DeathLink):
    """Share deaths with other DeathLink games. Incoming deaths lethally damage
    the current run, waiting until gameplay resumes if paused or editing upgrades.
    Deaths outside a living MultiworldGG run are ignored.
    """

    default = 1


class RequiredVictories(Range):
    """Multiworld-run victories required in addition to sending every randomized shipment."""

    display_name = "Required Victories"
    range_start = 0
    range_end = 50
    default = 0


# Unlocks are useful, not progression; native feats are optional, never logic gates.
class HiddenProgressionBalancing(ProgressionBalancing):
    visibility = Visibility.none


class HiddenAccessibility(Accessibility):
    visibility = Visibility.none


@dataclass
class PathogenicOptions(PerGameCommonOptions):
    progression_balancing: HiddenProgressionBalancing
    accessibility: HiddenAccessibility
    coin_checks: CoinChecks
    coin_amount: CoinAmount
    dna_checks: DNAChecks
    dna_amount: DNAAmount
    plasmid_fragment_checks: PlasmidFragmentChecks
    plasmid_fragment_amount: PlasmidFragmentAmount
    shop_unlocks: ShopUnlocks
    item_room_unlocks: ItemRoomUnlocks
    boss_reward_unlocks: BossRewardUnlocks
    level_up_unlocks: LevelUpUnlocks
    remote_characters: RemoteCharacters
    remote_plasmids: RemotePlasmids
    remote_loadouts: RemoteLoadouts
    remote_organelles: RemoteOrganelles
    remote_environment: RemoteEnvironment
    death_link: PathogenicDeathLink
    required_victories: RequiredVictories


class PathogenicWeb(WebWorld):
    tutorials = [Tutorial(
        "Multiworld Setup Guide",
        "Subscribe to the MultiworldGG Shop Workshop mod and connect Pathogenic to a multiworld.",
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
    item_name_to_id = {**FILLER_ITEM_IDS, **UNLOCK_ITEM_IDS}
    location_name_to_id = {
        f"Shop Shipment {index:03d}": 402938000 + index
        for index in range(1, MAX_SHIPMENTS + 1)
    }
    location_name_to_id.update(NATURAL_LOCATION_IDS)

    def enabled_unlocks(self) -> tuple:
        """Catalogue order is stable, independent of world RNG or dictionary order."""
        return tuple(entry for entry in CATALOG_ENTRIES
                     if getattr(self.options, CATEGORY_OPTIONS[entry["kind"]]).value)

    def shipment_count(self) -> int:
        return len(self.enabled_unlocks()) + self.options.coin_checks.value \
            + self.options.dna_checks.value + self.options.plasmid_fragment_checks.value

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
        for index in range(1, self.shipment_count() + 1):
            name = f"Shop Shipment {index:03d}"
            campaign.locations.append(
                PathogenicLocation(self.player, name, self.location_name_to_id[name], campaign)
            )
        for entry in self.enabled_unlocks():
            name = natural_location_name(entry)
            location = PathogenicLocation(
                self.player, name, self.location_name_to_id[name], campaign
            )
            location.place_locked_item(self.create_item(entry["name"]))
            campaign.locations.append(location)
        self.multiworld.completion_condition[self.player] = lambda state: all(
            state.can_reach_location(f"Shop Shipment {index:03d}", self.player)
            for index in range(1, self.shipment_count() + 1)
        )

    def create_items(self) -> None:
        entries = self.enabled_unlocks()
        self.multiworld.itempool.extend(self.create_item(entry["name"]) for entry in entries)
        for name, count in (
            (COINS, self.options.coin_checks.value),
            (DNA, self.options.dna_checks.value),
            (PLASMID_FRAGMENTS, self.options.plasmid_fragment_checks.value),
        ):
            self.multiworld.itempool.extend(self.create_item(name) for _ in range(count))

    def create_item(self, name: str) -> PathogenicItem:
        return PathogenicItem(
            name, ItemClassification.filler if name in FILLER_ITEM_IDS
            else ItemClassification.useful, self.item_name_to_id[name], self.player
        )

    def get_filler_item_name(self) -> str:
        return COINS

    def fill_slot_data(self) -> dict:
        return {
            "schema": 4,
            "catalog_schema": CATALOG_SCHEMA,
            "unlock_ids": [entry["id"] for entry in self.enabled_unlocks()],
            "checks": self.shipment_count(),
            "coin_amount": self.options.coin_amount.value,
            "dna_amount": self.options.dna_amount.value,
            "plasmid_fragment_amount": self.options.plasmid_fragment_amount.value,
            "sources": self.unlock_sources(),
            "death_link": bool(self.options.death_link.value),
            "required_victories": self.options.required_victories.value,
        }
