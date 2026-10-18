"""Catalogue facts and isolated APWorld generation contracts (no game assets required)."""
from collections import Counter
from contextlib import contextmanager
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch
import uuid
import zipfile
import zipimport


ROOT = Path(__file__).resolve().parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {name: module}):
        spec.loader.exec_module(module)
    return module


EXTRACTOR = load_module("_catalog_extractor", ROOT / "tools/extract_unlock_catalog.py")
CATALOG = json.loads((ROOT / "apworld/pathogenic/catalog.json").read_text(encoding="utf-8"))
ENTRIES = CATALOG["entries"]


@contextmanager
def fixture_root():
    # Keep generated test fixtures inside the project, never in system temp storage.
    root = ROOT / "tests" / (".catalog-fixture-" + uuid.uuid4().hex)
    root.mkdir()
    try:
        yield root
    finally:
        shutil.rmtree(root)


def write(root, path, text):
    destination = root / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8")


def load_world(archive=None):
    base = ModuleType("BaseClasses")

    class Classification:
        filler = "filler"
        useful = "useful"

    class Item:
        def __init__(self, name, classification, code, player):
            self.name, self.classification, self.code, self.player = (
                name, classification, code, player)

    class Location:
        def __init__(self, player, name, address, parent):
            self.player, self.name, self.address, self.parent_region = (
                player, name, address, parent)

        def place_locked_item(self, item):
            self.item, self.locked = item, True

    class Region:
        def __init__(self, name, player, multiworld):
            self.name, self.locations = name, []

        def connect(self, region):
            self.connected_region = region

    base.Item, base.ItemClassification = Item, Classification
    base.Location, base.Region = Location, Region
    base.Tutorial = lambda *args: args
    options = ModuleType("Options")
    for name in ("Accessibility", "DeathLink", "DefaultOnToggle", "PerGameCommonOptions",
                 "ProgressionBalancing", "Range"):
        setattr(options, name, type(name, (), {}))
    options.OptionError = ValueError
    options.Visibility = SimpleNamespace(none=0)
    auto = ModuleType("worlds.AutoWorld")
    auto.WebWorld, auto.World = type("WebWorld", (), {}), type("World", (), {})
    modules = {"BaseClasses": base, "Options": options,
               "worlds": ModuleType("worlds"), "worlds.AutoWorld": auto}
    with patch.dict(sys.modules, modules):
        if archive is not None:
            sys.modules.pop("pathogenic", None)
            with patch.object(sys, "path", [str(archive), *sys.path]):
                return __import__("pathogenic")
        return load_module("_catalog_apworld", ROOT / "apworld/pathogenic/__init__.py")


WORLD = load_world()


def make_world(coin_checks=0, dna_checks=0, plasmid_fragment_checks=0, disabled=(), required_victories=0):
    world = WORLD.PathogenicWorld()
    world.player = 1
    world.player_name = "Test Player"
    world.multiworld = SimpleNamespace(
        regions=[], itempool=[], completion_condition={})
    values = {name: SimpleNamespace(value=name not in disabled)
              for name in WORLD.CATEGORY_OPTIONS.values()}
    values.update({name: SimpleNamespace(value=True) for name in
                   ("shop_unlocks", "item_room_unlocks", "boss_reward_unlocks",
                    "level_up_unlocks", "death_link")})
    values.update({name: SimpleNamespace(value=value) for name, value in {
        "coin_checks": coin_checks,
        "coin_amount": 15,
        "dna_checks": dna_checks,
        "dna_amount": 1,
        "plasmid_fragment_checks": plasmid_fragment_checks,
        "plasmid_fragment_amount": 1,
        "required_victories": required_victories,
    }.items()})
    world.options = SimpleNamespace(**values)
    return world


class CatalogFactsTests(unittest.TestCase):
    def entry(self, name):
        return next(entry for entry in ENTRIES if entry["name"] == name)

    def test_schema_counts_and_unique_network_ids(self):
        EXTRACTOR.validate_catalog(CATALOG)
        self.assertEqual(Counter(entry["kind"] for entry in ENTRIES), {
            "character": 5, "plasmid": 216, "loadout": 68,
            "organelle": 14, "environment": 6})
        self.assertEqual(len(WORLD.UNLOCK_ITEM_IDS), len(ENTRIES))
        self.assertEqual(len(WORLD.NATURAL_LOCATION_IDS), len(ENTRIES))
        self.assertTrue(all(isinstance(entry["condition"], str) for entry in ENTRIES))
        self.assertTrue(set(WORLD.UNLOCK_ITEM_IDS.values()).isdisjoint(
            WORLD.NATURAL_LOCATION_IDS.values()))

    def test_plasmids_preserve_character_node_identity(self):
        ordinary = [entry for entry in ENTRIES
                    if entry["kind"] == "plasmid" and not entry.get("standalone")]
        self.assertEqual(Counter(entry["parasite"] for entry in ordinary),
                         {0: 36, 1: 30, 2: 30, 3: 30, 4: 30, 5: 30, 7: 30})
        identities = {(entry["parasite"], entry["node"]) for entry in ordinary}
        self.assertEqual(len(identities), len(ordinary))
        for entry in ordinary:
            self.assertEqual(entry["condition"], "")
            self.assertEqual(entry["save_key"], entry["node"])
            self.assertEqual(entry["section"], f"plasmids{entry['parasite']}")
            self.assertNotIn("starting_plasmid", entry["scene"])
        # The same translated effect may occupy several independent map nodes.
        labels = Counter(entry["name"].split(" [")[0] for entry in ordinary)
        self.assertGreater(max(labels.values()), 1)

    def test_unused_standalone_plasmids_are_excluded(self):
        self.assertFalse(any(entry.get("standalone") for entry in ENTRIES))
        self.assertTrue(EXTRACTOR.RETIRED_IDS.keys().isdisjoint(
            entry["key"] for entry in ENTRIES))
        self.assertEqual([entry["id"] for entry in ENTRIES], list(range(309)))

    def test_only_known_native_condition_alias_is_preserved(self):
        aliases = {}
        for entry in ENTRIES:
            if entry.get("condition"):
                aliases.setdefault(entry["condition"], []).append(entry["id"])
        self.assertEqual({key: ids for key, ids in aliases.items() if len(ids) > 1}, {
            "res://scn/metaprogression/loadouts/loadout_collector.tres::Resource_kwm52":
                [35, 38]})
        self.assertNotEqual(ENTRIES[35]["resource"], ENTRIES[38]["resource"])

    def test_loadout_gates_are_not_random_drop_gates(self):
        loadout = self.entry("Bacterium Loadout: Sequence Scrambler")
        organelle = self.entry("Organelle: Sequence Scrambler")
        self.assertEqual((loadout["threshold"], loadout["comparison"]), (25, ">="))
        self.assertTrue(loadout["stat"].endswith("/shop_reroll_stat.tres"))
        self.assertEqual((organelle["threshold"], organelle["comparison"]), (100, ">="))
        self.assertTrue(organelle["stat"].endswith("/pedestal_rewards_collected_stat.tres"))
        self.assertNotEqual(loadout["condition"], organelle["condition"])

    def test_ballistic_flagellum_is_lung_at_most_twenty(self):
        entry = self.entry("Bacterium Loadout: Ballistic Flagellum")
        self.assertEqual((entry["threshold"], entry["comparison"]), (20, "<="))
        self.assertTrue(entry["stat"].endswith("/lung_boss_beaten_timed_stat.tres"))

    def test_bodypart_subclass_gate_is_included(self):
        self.assertTrue(any(entry["kind"] == "organelle" and
                            entry["resource"].endswith("/melee_on_ranged.tres")
                            for entry in ENTRIES))

    def test_duplicate_fields_and_invalid_ids_fail(self):
        for field in ("id", "key", "name"):
            broken = deepcopy(CATALOG)
            broken["entries"][1][field] = broken["entries"][0][field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                EXTRACTOR.validate_catalog(broken)
        broken = deepcopy(CATALOG)
        broken["entries"][0]["id"] = True
        with self.assertRaises(ValueError):
            EXTRACTOR.validate_catalog(broken)

    def test_regeneration_preserves_ids_and_is_deterministic(self):
        facts = [{key: value for key, value in entry.items() if key != "id"}
                 for entry in ENTRIES]
        addition = deepcopy(facts[0])
        addition.update(key="character:new", name="Character: New")
        with patch.object(EXTRACTOR.Extractor, "__init__", return_value=None):
            with patch.object(EXTRACTOR.Extractor, "extract",
                              return_value=list(reversed(facts)) + [addition]):
                first = EXTRACTOR.build_catalog(ROOT, CATALOG)
            with patch.object(EXTRACTOR.Extractor, "extract",
                              return_value=[addition] + facts):
                second = EXTRACTOR.build_catalog(ROOT, CATALOG)
        self.assertEqual(first, second)
        self.assertEqual(first["entries"][:-1], ENTRIES)
        self.assertEqual(first["entries"][-1]["id"], 311)

    def test_missing_previous_identity_fails(self):
        facts = [{key: value for key, value in entry.items() if key != "id"}
                 for entry in ENTRIES[1:]]
        with patch.object(EXTRACTOR.Extractor, "__init__", return_value=None):
            with patch.object(EXTRACTOR.Extractor, "extract", return_value=facts):
                with self.assertRaisesRegex(ValueError, "disappeared"):
                    EXTRACTOR.build_catalog(ROOT, CATALOG)

    @unittest.skipUnless(os.environ.get("PATHOGENIC_RECOVERED"), "private resources not supplied")
    def test_private_regeneration_matches_frozen_catalog(self):
        self.assertEqual(EXTRACTOR.build_catalog(
            Path(os.environ["PATHOGENIC_RECOVERED"]), CATALOG), CATALOG)
        root = Path(os.environ["PATHOGENIC_RECOVERED"])
        group = EXTRACTOR.Document(root, "res://scn/player/bodyparts/all_bodyparts.tres")
        pool = json.loads(group.resource()["paths"])
        self.assertTrue(all(entry["resource"] in pool for entry in ENTRIES
                            if entry["kind"] == "organelle"))


class ParserTests(unittest.TestCase):
    def test_map_connections_require_reachable_valid_endpoints(self):
        with fixture_root() as root:
            write(root, "translations/translations.csv", "key,en\n")
            text = '''[gd_scene format=3]
[ext_resource type="PackedScene" path="res://starting_plasmid.tscn" id="start"]
[ext_resource type="PackedScene" path="res://effect.tscn" id="effect"]
[node name="Map" type="Node2D"]
[node name="StartingPlasmid" parent="." instance=ExtResource("start")]
[node name="Effect" parent="." instance=ExtResource("effect")]
[node name="Connection" type="Node2D" parent="StartingPlasmid"]
from = NodePath("..")
to = NodePath("../../Effect")
'''
            extractor = EXTRACTOR.Extractor(root)
            write(root, "map.tscn", text)
            extractor.validate_map_connections(EXTRACTOR.Document(root, "res://map.tscn"))
            write(root, "map.tscn", text.replace("../../Effect", "../../Missing"))
            with self.assertRaisesRegex(ValueError, "Missing map connection target"):
                extractor.validate_map_connections(EXTRACTOR.Document(root, "res://map.tscn"))
            write(root, "map.tscn", text.split('[node name="Connection"')[0])
            with self.assertRaisesRegex(ValueError, "Unreachable plasmid nodes"):
                extractor.validate_map_connections(EXTRACTOR.Document(root, "res://map.tscn"))

    def test_inheritance_translation_and_gate_origin(self):
        with fixture_root() as root:
            write(root, "translations/translations.csv",
                  'key,en\nfixture_name,[b]Fixture[/b]\n')
            write(root, "base.tscn", '''[gd_scene format=3]
[ext_resource type="Resource" path="res://mutation.tres" id="mutation"]
[node name="Base" type="Node2D"]
mutation_res = ExtResource("mutation")
ui_name = "fixture_name"
''')
            write(root, "derived.tscn", '''[gd_scene format=3]
[ext_resource type="PackedScene" path="res://base.tscn" id="base"]
[node name="Derived" instance=ExtResource("base")]
''')
            write(root, "gate.tres", '''[gd_resource type="Resource" format=3]
[ext_resource type="Resource" path="res://stat.tres" id="stat"]
[sub_resource type="Resource" id="Gate"]
stat = ExtResource("stat")
threshold = 20.0
global = true
[resource]
unlock = SubResource("Gate")
''')
            write(root, "stat.tres", '''[gd_resource type="Resource" format=3]
[resource]
aggregation = 2
''')
            extractor = EXTRACTOR.Extractor(root)
            effective = extractor.scene("res://derived.tscn")
            owner, value = effective["mutation_res"]
            self.assertEqual(owner.reference(value), "res://mutation.tres")
            self.assertEqual(extractor.label(effective["ui_name"][1]), "Fixture")
            gate_doc = extractor.document("res://gate.tres")
            gate = extractor.gate(gate_doc, gate_doc.resource()["unlock"])
            self.assertEqual(gate["condition"], "res://gate.tres::Gate")
            self.assertEqual((gate["threshold"], gate["comparison"], gate["global"]),
                             (20, "<=", True))
            with self.assertRaisesRegex(ValueError, "Unresolved English"):
                extractor.label('"missing_name"')
            with self.assertRaisesRegex(ValueError, "Missing external resource"):
                gate_doc.reference('ExtResource("missing")')
            with self.assertRaises(ValueError):
                gate_doc.reference_list('[SubResource("Gate"), null]')

    def test_scene_inheritance_cycle_fails(self):
        with fixture_root() as root:
            write(root, "translations/translations.csv", "key,en\n")
            write(root, "cycle.tscn", '''[gd_scene format=3]
[ext_resource type="PackedScene" path="res://cycle.tscn" id="self"]
[node name="Cycle" instance=ExtResource("self")]
''')
            with self.assertRaisesRegex(ValueError, "cycle"):
                EXTRACTOR.Extractor(root).scene("res://cycle.tscn")


class APWorldTests(unittest.TestCase):
    def test_required_victories_bounds_and_slot_data(self):
        self.assertEqual((WORLD.RequiredVictories.range_start, WORLD.RequiredVictories.range_end), (0, 50))
        self.assertEqual(WORLD.RequiredVictories.default, 0)
        for victories in (0, 1, 50):
            world = make_world(required_victories=victories)
            world.generate_early()
            self.assertEqual(world.fill_slot_data()["required_victories"], victories)
            self.assertEqual(world.shipment_count(), len(ENTRIES))

    def test_currency_option_bounds(self):
        for checks, amount in (
                (WORLD.CoinChecks, WORLD.CoinAmount),
                (WORLD.DNAChecks, WORLD.DNAAmount),
                (WORLD.PlasmidFragmentChecks, WORLD.PlasmidFragmentAmount)):
            self.assertEqual((checks.range_start, checks.range_end), (0, 10000))
            self.assertEqual((amount.range_start, amount.range_end), (1, 10000))
        self.assertEqual(WORLD.CoinChecks.default, 0)
        self.assertEqual(WORLD.CoinAmount.default, 15)
        self.assertEqual(WORLD.DNAAmount.default, 1)
        self.assertEqual(WORLD.PlasmidFragmentAmount.default, 1)

    def test_zero_filler_checks_still_fits_enabled_unlocks(self):
        world = make_world()
        world.generate_early()
        world.create_regions()
        world.create_items()
        self.assertEqual(world.shipment_count(), len(ENTRIES))
        self.assertEqual(len(world.multiworld.itempool), len(ENTRIES))
        self.assertEqual(world.fill_slot_data()["checks"], len(ENTRIES))

    def test_zero_shipments_without_remote_categories(self):
        world = make_world(disabled=tuple(WORLD.CATEGORY_OPTIONS.values()))
        world.generate_early()
        world.create_regions()
        world.create_items()
        self.assertEqual(world.multiworld.itempool, [])
        self.assertEqual(world.multiworld.regions[1].locations, [])
        self.assertEqual(world.fill_slot_data()["checks"], 0)
        self.assertTrue(world.multiworld.completion_condition[1](None))

    def test_packaged_world_imports_catalog_from_zip(self):
        with fixture_root() as root:
            archive = root / "pathogenic.apworld"
            with zipfile.ZipFile(archive, "w") as package:
                for filename in ("__init__.py", "catalog.json", "archipelago.json"):
                    package.write(ROOT / "apworld/pathogenic" / filename,
                                  "pathogenic/" + filename)
            world = load_world(archive)
            self.assertIsInstance(world.__loader__, zipimport.zipimporter)
            self.assertEqual(world.CATALOG, CATALOG)
            self.assertEqual(world.UNLOCK_ITEM_IDS, WORLD.UNLOCK_ITEM_IDS)
            self.assertEqual(world.NATURAL_LOCATION_IDS, WORLD.NATURAL_LOCATION_IDS)
            with zipfile.ZipFile(archive) as package:
                manifest = json.loads(package.read("pathogenic/archipelago.json"))
            self.assertEqual(manifest["world_version"], "0.2.2")

    def test_default_pool_and_optional_natural_self_rewards(self):
        world = make_world()
        world.generate_early()
        world.create_regions()
        world.create_items()
        self.assertEqual(world.shipment_count(), len(ENTRIES))
        self.assertEqual(len(world.multiworld.itempool), len(ENTRIES))
        self.assertEqual({item.name for item in world.multiworld.itempool},
                         set(WORLD.UNLOCK_ITEM_IDS))
        locations = world.multiworld.regions[1].locations
        self.assertEqual(len(locations), 2 * len(ENTRIES))
        for location in locations[len(ENTRIES):]:
            self.assertTrue(location.locked)
            self.assertEqual(location.item.player, world.player)
            self.assertEqual(location.name, "Earn " + location.item.name)
            self.assertEqual(location.item.classification, "useful")

    def test_all_categories_off_preserves_filler_campaign(self):
        world = make_world(coin_checks=20, disabled=tuple(WORLD.CATEGORY_OPTIONS.values()))
        world.create_regions()
        world.create_items()
        self.assertEqual(len(world.multiworld.regions[1].locations), 20)
        self.assertEqual(len(world.multiworld.itempool), 20)
        self.assertTrue(all(item.name == WORLD.COINS and item.classification == "filler"
                            for item in world.multiworld.itempool))
        self.assertEqual(world.fill_slot_data()["unlock_ids"], [])
        self.assertEqual(world.fill_slot_data()["schema"], 4)

    def test_subset_and_filler_remainder(self):
        disabled = tuple(option for kind, option in WORLD.CATEGORY_OPTIONS.items()
                         if kind != "character")
        world = make_world(coin_checks=95, disabled=disabled)
        world.create_regions()
        world.create_items()
        self.assertEqual(world.shipment_count(), 100)
        self.assertEqual(len(world.multiworld.itempool), 100)
        self.assertEqual(sum(item.classification == "useful"
                             for item in world.multiworld.itempool), 5)
        self.assertEqual(len(world.multiworld.regions[1].locations), 105)
        slot = world.fill_slot_data()
        self.assertEqual(set(slot), {
            "schema", "catalog_schema", "unlock_ids", "checks", "coin_amount",
            "dna_amount", "plasmid_fragment_amount", "sources", "death_link", "required_victories"})
        self.assertEqual((slot["schema"], slot["catalog_schema"], slot["checks"]),
                         (4, 1, 100))
        self.assertEqual(slot["unlock_ids"], [
            entry["id"] for entry in ENTRIES if entry["kind"] == "character"])

    def test_mixed_currency_check_counts_and_amounts(self):
        world = make_world(coin_checks=2, dna_checks=3, plasmid_fragment_checks=4)
        world.options.dna_amount.value = 250
        world.options.plasmid_fragment_amount.value = 6
        world.create_items()
        self.assertEqual(world.shipment_count(), len(ENTRIES) + 9)
        fillers = [item for item in world.multiworld.itempool if item.classification == "filler"]
        self.assertEqual(Counter(item.name for item in fillers), {
            WORLD.COINS: 2, WORLD.DNA: 3, WORLD.PLASMID_FRAGMENTS: 4})
        slot = world.fill_slot_data()
        self.assertEqual((slot["coin_amount"], slot["dna_amount"],
                          slot["plasmid_fragment_amount"]), (15, 250, 6))

    def test_maximum_currency_checks_fit_fixed_location_table(self):
        world = make_world(coin_checks=10000, dna_checks=10000, plasmid_fragment_checks=10000)
        self.assertEqual(world.shipment_count(), WORLD.MAX_SHIPMENTS)
        self.assertLessEqual(world.shipment_count(), len(WORLD.PathogenicWorld.location_name_to_id))
        self.assertEqual(WORLD.MAX_SHIPMENTS, 30309)

    def test_goal_uses_shipments_not_native_feats(self):
        world = make_world()
        world.create_regions()
        visited = []
        state = SimpleNamespace(can_reach_location=lambda name, player:
                                visited.append(name) is None)
        self.assertTrue(world.multiworld.completion_condition[1](state))
        self.assertEqual(visited, [f"Shop Shipment {index:03d}"
                                  for index in range(1, len(ENTRIES) + 1)])

    def test_disabled_categories_keep_static_name_maps(self):
        world = make_world(disabled=tuple(WORLD.CATEGORY_OPTIONS.values()))
        self.assertEqual(len(world.item_name_to_id), len(ENTRIES) + 3)
        self.assertEqual(len(world.location_name_to_id),
                         WORLD.MAX_SHIPMENTS + len(ENTRIES))
        self.assertEqual(world.item_name_to_id[WORLD.COINS], 402939001)
        self.assertEqual(world.item_name_to_id[WORLD.DNA], 402939002)
        self.assertEqual(world.item_name_to_id[WORLD.PLASMID_FRAGMENTS], 402939003)
        self.assertEqual(world.location_name_to_id["Shop Shipment 001"], 402938001)
        for entry in ENTRIES:
            self.assertEqual(world.item_name_to_id[entry["name"]], 402960000 + entry["id"])
            self.assertEqual(world.location_name_to_id["Earn " + entry["name"]],
                             402970000 + entry["id"])

    def test_category_defaults_and_generation_are_deterministic(self):
        for kind in WORLD.CATEGORY_OPTIONS:
            option_type = getattr(WORLD, "Remote" + {
                "character": "Characters", "plasmid": "Plasmids", "loadout": "Loadouts",
                "organelle": "Organelles", "environment": "Environment"}[kind])
            self.assertTrue(issubclass(option_type, WORLD.DefaultOnToggle))
        first, second = make_world(), make_world()
        first.create_items()
        second.create_items()
        self.assertEqual(first.fill_slot_data(), second.fill_slot_data())
        self.assertEqual([item.code for item in first.multiworld.itempool],
                         [item.code for item in second.multiworld.itempool])

    def test_no_acquisition_sources_still_rejected(self):
        world = make_world()
        for source in ("shop_unlocks", "item_room_unlocks",
                       "boss_reward_unlocks", "level_up_unlocks"):
            getattr(world.options, source).value = False
        with self.assertRaisesRegex(ValueError, "enable at least one"):
            world.generate_early()


if __name__ == "__main__":
    unittest.main()
