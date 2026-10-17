import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import sys
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
with patch.dict(sys.modules, {"install": installer}):
    demo = module("build_demo")

CONFIG = (
    'config_version=5\n[application]\nconfig/name="Pathogenic"\n'
    'run/main_scene="uid://original"\n[autoload]\nOriginal="*uid://original"\n'
    '[steam]\ninitialization/app_id=4029380\n[sentry]\noptions/dsn="test-only"\n'
)


class DemoBuildTests(unittest.TestCase):
    def test_config_preserves_game_and_puts_bootstrap_first(self):
        text = demo.project_config(CONFIG)
        self.assertIn('initialization/app_id=4029380', text)
        self.assertIn('run/main_scene="uid://original"', text)
        self.assertIn('[autoload]\nArchipelagoBootstrap=', text)
        self.assertIn('Original="*uid://original"', text)
        self.assertIn('config/custom_user_dir_name="Pathogenic Archipelago"', text)
        self.assertIn('config/use_custom_user_dir=true', text)
        self.assertIn('options/dsn=""', text)
        self.assertNotIn('test-only', text)

    def test_config_rejects_wrong_app_or_missing_telemetry_setting(self):
        for text in (CONFIG.replace("4029380", "3808690"),
                     CONFIG + "\ninitialization/app_id=3808690\n",
                     CONFIG.replace('options/dsn="test-only"\n', ""),
                     CONFIG + "\n[autoload]\n"):
            with self.assertRaises(ValueError):
                demo.project_config(text)

    def test_config_rejects_repatch_and_ambiguous_save_directory(self):
        for text in (demo.project_config(CONFIG),
                     CONFIG.replace("[application]", "[application]\nconfig/use_custom_user_dir=false")):
            with self.assertRaises(ValueError):
                demo.project_config(text)
        with self.assertRaises(ValueError):
            demo.project_config(CONFIG, "../original")

    def test_launcher_refuses_unowned_and_symlink_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher = root / "launch.command"
            launcher.write_text("user data")
            with self.assertRaisesRegex(ValueError, "unowned"):
                demo.write_launcher(launcher, root / "game")
            link = root / "link.command"
            link.symlink_to(launcher)
            with self.assertRaisesRegex(ValueError, "symlink"):
                demo.write_launcher(link, root / "game")
            self.assertEqual(launcher.read_text(), "user data")

    def test_launcher_quotes_paths_and_replaces_only_owned_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher = root / "launch.command"
            demo.write_launcher(launcher, root / "Game With Spaces")
            self.assertTrue(launcher.read_text().startswith(demo.LAUNCHER_HEADER))
            self.assertIn('Game With Spaces\' "$@"', launcher.read_text())
            demo.write_launcher(launcher, root / "replacement")
            self.assertIn("replacement", launcher.read_text())
            self.assertEqual(list(root.glob(".ap-launcher-*")), [])

    def test_failed_build_keeps_working_launcher_and_incomplete_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            game = root / "Original.app"
            resources = game / "Contents/Resources"
            resources.mkdir(parents=True)
            (resources / "Pathogenic.pck").write_bytes(b"original pack")
            (root / "dist").mkdir()
            with zipfile.ZipFile(root / "dist/Local-ArchipelagoShop.zip", "w") as archive:
                archive.writestr("original-mod.gd", "extends Node\n")
            launcher = root / "launch-modded.command"
            launcher.write_text(demo.LAUNCHER_HEADER + "old working launcher\n")
            gdre = root / "gdre"
            gdre.touch()

            def fake_run(command, _log):
                destination = Path(next(arg.split("=", 1)[1] for arg in command
                                        if arg.startswith("--output=")))
                if any(arg.startswith("--recover=") for arg in command):
                    destination.mkdir()
                    (destination / "project.godot").write_text(CONFIG)
                else:
                    destination.write_bytes(b"patched pack")

            with patch.object(demo, "ROOT", root), \
                    patch.object(demo, "verify_game", return_value=game), \
                    patch.object(demo, "run", side_effect=fake_run), \
                    patch.object(demo, "smoke_test", side_effect=RuntimeError("smoke failed")):
                with self.assertRaisesRegex(RuntimeError, "smoke failed"):
                    demo.build_demo(game, gdre)
            self.assertEqual(launcher.read_text(), demo.LAUNCHER_HEADER + "old working launcher\n")
            metadata = next((root / "local-builds").glob("*/build.json"))
            self.assertEqual(json.loads(metadata.read_text())["status"], "incomplete")
            self.assertEqual((resources / "Pathogenic.pck").read_bytes(), b"original pack")

    def test_smoke_requires_actual_packed_scene_and_save_isolation(self):
        expected = (
            f"AP_BOOTSTRAP_SMOKE user_dir={Path.home() / 'Library/Application Support' / demo.USER_DIR}"
            " extended=true scene_extended=true client=true\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "test.log"
            def run_with_output(command, **kwargs):
                kwargs["stdout"].write(expected)
                return type("Result", (), {"returncode": 0})()
            with patch.object(demo.subprocess, "run", side_effect=run_with_output):
                demo.smoke_test(root, log)
            with patch.object(demo.subprocess, "run", return_value=type("Result", (), {"returncode": 0})()):
                with self.assertRaisesRegex(RuntimeError, "validation failed"):
                    demo.smoke_test(root, log)


class ToolingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pathogenic-ap-tooling-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.game = self.root / "game/Pathogenic.app"
        for relative in ("Contents/MacOS/Pathogenic", "Contents/Resources/Pathogenic.pck"):
            path = self.game / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        self.dist = self.root / "dist"
        self.dist.mkdir()
        self.archive = self.dist / installer.MOD_NAME
        self.write_mod()
        self.mods = self.game.parent / "mods"
        self.mods.mkdir()
        digest = hashlib.sha256(b"fixture").hexdigest()
        for name, value in (("ROOT", self.root), ("EXECUTABLE_SHA256", digest), ("PCK_SHA256", digest)):
            patched = patch.object(installer, name, value)
            patched.start()
            self.addCleanup(patched.stop)

    def write_mod(self, namespace="Local", version=1):
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("mods-unpacked/Local-ArchipelagoShop/manifest.json",
                             json.dumps({"namespace": namespace, "name": "ArchipelagoShop", "version": version}))

    def test_reproducible_archive(self):
        source = self.root / "original.gd"
        source.write_text("extends Node\n")
        output = self.dist / "test.zip"
        first = builder.archive(output, [(source, "mod/original.gd")])
        second = builder.archive(output, [(source, "mod/original.gd")])
        self.assertEqual(first, second)
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(archive.namelist(), ["mod/original.gd"])
            self.assertEqual(archive.read("mod/original.gd"), source.read_bytes())

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

    def test_refuse_changed_game_data(self):
        (self.game / "Contents/Resources/Pathogenic.pck").write_bytes(b"updated")
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            installer.install(self.game)
        self.assertFalse((self.mods / installer.MOD_NAME).exists())

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
        (self.game.parent / "mods-unpacked/Local-ArchipelagoShop").mkdir(parents=True)
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
