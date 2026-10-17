import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


builder = module("build")
installer = module("install")
workshop = module("workshop_vdf")


class WorkshopVdfTests(unittest.TestCase):
    def test_vdf_targets_pathogenic_and_escapes_values(self):
        with tempfile.TemporaryDirectory() as directory:
            text = workshop.vdf(Path(directory), "0", None, "private", 'say "hi" \\ there')
        self.assertTrue(text.startswith('"workshopitem"\n{\n'))
        self.assertIn('\t"appid"\t"3808690"\n', text)
        self.assertIn('\t"publishedfileid"\t"0"\n', text)
        self.assertIn('\t"visibility"\t"2"\n', text)
        self.assertIn('\t"changenote"\t"say \\"hi\\" \\\\ there"\n', text)
        self.assertNotIn("previewfile", text)

    def test_vdf_requires_existing_content_and_preview(self):
        with self.assertRaises(FileNotFoundError):
            workshop.vdf(ROOT / "missing", "0", None, "private", "")
        with self.assertRaises(FileNotFoundError):
            workshop.vdf(ROOT, "0", ROOT / "missing.png", "private", "")


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pathogenic-ap-build-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for folder in ("mods-unpacked", "apworld"):
            shutil.copytree(ROOT / folder, self.root / folder)

    def test_reproducible_archive(self):
        source = self.root / "original.gd"
        source.write_text("extends Node\n")
        output = self.root / "dist/test.zip"
        first = builder.archive(output, [(source, "mod/original.gd")])
        second = builder.archive(output, [(source, "mod/original.gd")])
        self.assertEqual(first, second)
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(archive.namelist(), ["mod/original.gd"])
            self.assertEqual(archive.read("mod/original.gd"), source.read_bytes())

    def test_build_stages_only_the_mod_zip_for_the_workshop(self):
        stale = self.root / "dist/workshop/stale.txt"
        stale.parent.mkdir(parents=True)
        stale.write_text("old upload")
        hashes = builder.build(self.root)
        dist = self.root / "dist"
        self.assertEqual(sorted(hashes), [f"{builder.MOD_ID}.zip", "pathogenic.apworld"])
        self.assertEqual([p.name for p in (dist / "workshop").iterdir()], [f"{builder.MOD_ID}.zip"])
        self.assertEqual((dist / "workshop" / f"{builder.MOD_ID}.zip").read_bytes(),
                         (dist / f"{builder.MOD_ID}.zip").read_bytes())
        with zipfile.ZipFile(dist / f"{builder.MOD_ID}.zip") as archive:
            self.assertEqual(sorted(archive.namelist()), sorted(
                f"mods-unpacked/{builder.MOD_ID}/{name}" for name in builder.MOD_FILES))
        with zipfile.ZipFile(dist / "pathogenic.apworld") as archive:
            self.assertIn("pathogenic/__init__.py", archive.namelist())
        self.assertEqual(builder.build(self.root), hashes)

    def test_manifest_id_must_match_directory(self):
        path = self.root / "mods-unpacked" / builder.MOD_ID / "manifest.json"
        data = json.loads(path.read_text())
        data["namespace"] = "Local"
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "does not match"):
            builder.build(self.root)

    def test_release_tag_must_match_mod_and_world_versions(self):
        version = builder.manifest(self.root)["version_number"]
        self.assertEqual(builder.check_version(f"v{version}", self.root), version)
        with self.assertRaisesRegex(ValueError, "must equal"):
            builder.check_version("v99.0.0", self.root)
        world = self.root / "apworld/pathogenic/archipelago.json"
        data = json.loads(world.read_text())
        data["world_version"] = "99.0.0"
        world.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "must equal"):
            builder.check_version(f"v{version}", self.root)

    def test_shipped_manifest_satisfies_mod_loader(self):
        data = builder.manifest()
        for key in ("name", "namespace", "version_number", "website_url", "description",
                    "dependencies", "extra"):
            self.assertIn(key, data)
        godot = data["extra"]["godot"]
        for key in ("authors", "compatible_mod_loader_version", "compatible_game_version"):
            self.assertIn(key, godot)
        for name in (data["name"], data["namespace"]):
            self.assertRegex(name, r"^[A-Za-z0-9_]{3,}$")
        self.assertRegex(data["version_number"], r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pathogenic-ap-tooling-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.steamapps = self.root / "steamapps"
        self.game = self.steamapps / "common/Pathogenic/Pathogenic.app"
        pck = self.game / "Contents/Resources/Pathogenic.pck"
        pck.parent.mkdir(parents=True)
        pck.write_bytes(b"fixture")
        (self.game.parent / "steam_data.json").write_text('{"app_id": "3808690"}')
        self.dist = self.root / "dist"
        self.dist.mkdir()
        self.archive = self.dist / installer.MOD_NAME
        self.write_mod()
        self.mods = self.game.parent / "mods"
        self.mods.mkdir()
        patched = patch.object(installer, "ROOT", self.root)
        patched.start()
        self.addCleanup(patched.stop)

    def write_mod(self, namespace="ViMaSter", version=1):
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr(f"mods-unpacked/{installer.MOD_ID}/manifest.json",
                             json.dumps({"namespace": namespace, "name": "ArchipelagoShop",
                                         "version": version}))

    def test_replace_only_owned_mod_and_backup(self):
        other = self.mods / "unrelated.zip"
        other.write_bytes(b"preserve me")
        target = installer.install(self.game)
        original = target.read_bytes()
        self.write_mod(version=2)
        installer.install(self.game)
        self.assertEqual(target.read_bytes(), self.archive.read_bytes())
        self.assertEqual((self.dist / "previous-install.zip").read_bytes(), original)
        self.assertEqual(other.read_bytes(), b"preserve me")
        self.assertFalse((self.mods / (installer.MOD_NAME + ".installing")).exists())

    def test_uninstall_removes_only_owned_zip(self):
        other = self.mods / "unrelated.zip"
        other.write_bytes(b"preserve me")
        target = installer.install(self.game)
        installer.uninstall(self.game)
        self.assertFalse(target.exists())
        self.assertEqual(other.read_bytes(), b"preserve me")

    def test_refuse_demo_or_unknown_app(self):
        for content in ('{"app_id": "4029380"}', "not json"):
            (self.game.parent / "steam_data.json").write_text(content)
            with self.assertRaises(ValueError):
                installer.install(self.game)
        (self.game.parent / "steam_data.json").unlink()
        with self.assertRaisesRegex(ValueError, "Cannot read"):
            installer.install(self.game)
        self.assertFalse((self.mods / installer.MOD_NAME).exists())

    def test_warn_about_subscribed_workshop_copy(self):
        subscribed = self.steamapps / "workshop/content/3808690/123/" / installer.MOD_NAME
        subscribed.parent.mkdir(parents=True)
        subscribed.write_bytes(b"workshop")
        self.assertEqual(installer.workshop_copy(self.game.resolve()), subscribed.resolve())
        with patch("builtins.print") as printed:
            installer.install(self.game)
        self.assertTrue(any("WARNING" in str(call) for call in printed.call_args_list))

    def test_refuse_unowned_previous_install(self):
        self.write_mod(namespace="SomeoneElse")
        target = self.mods / installer.MOD_NAME
        target.write_bytes(self.archive.read_bytes())
        original = target.read_bytes()
        self.write_mod()
        with self.assertRaisesRegex(ValueError, "not owned"):
            installer.install(self.game)
        self.assertEqual(target.read_bytes(), original)

    def test_refuse_symlink_destination(self):
        preserved = self.root / "preserved"
        preserved.write_bytes(b"preserve")
        (self.mods / installer.MOD_NAME).symlink_to(preserved)
        with self.assertRaisesRegex(ValueError, "symlink"):
            installer.install(self.game)
        self.assertEqual(preserved.read_bytes(), b"preserve")

    def test_refuse_stale_stage_without_deleting_it(self):
        stage = self.mods / (installer.MOD_NAME + ".installing")
        stage.write_bytes(b"not ours")
        with self.assertRaisesRegex(ValueError, "Stale"):
            installer.install(self.game)
        self.assertEqual(stage.read_bytes(), b"not ours")

    def test_refuse_conflicting_unpacked_copy(self):
        (self.game.parent / "mods-unpacked" / installer.MOD_ID).mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "Conflicting"):
            installer.install(self.game)

    def test_corrupt_archive_does_not_replace_previous_install(self):
        target = installer.install(self.game)
        previous = target.read_bytes()
        self.archive.write_bytes(b"corrupt")
        with self.assertRaises(zipfile.BadZipFile):
            installer.install(self.game)
        self.assertEqual(target.read_bytes(), previous)
        self.assertFalse((self.mods / (installer.MOD_NAME + ".installing")).exists())


if __name__ == "__main__":
    unittest.main()
