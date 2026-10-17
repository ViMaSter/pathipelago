import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("generation", ROOT / "example/generate.py")
generation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generation)


class GenerationTests(unittest.TestCase):
    def release_response(self, **overrides):
        data = {"tag_name": "0.7.273", "draft": False, "prerelease": False, **overrides}
        return io.BytesIO(json.dumps(data).encode())

    def test_latest_stable_and_invalid_metadata(self):
        with patch.object(generation, "urlopen", return_value=self.release_response()) as fetch:
            self.assertEqual(generation.latest_release(), "0.7.273")
        self.assertEqual(fetch.call_args.args[0].full_url, generation.LATEST)
        for overrides in ({"draft": True}, {"prerelease": True}, {"tag_name": "../bad"},
                          {"tag_name": "0.7.273/extra"}, {"tag_name": None}):
            with self.subTest(overrides=overrides), patch.object(
                    generation, "urlopen", return_value=self.release_response(**overrides)):
                with self.assertRaises(ValueError):
                    generation.latest_release()

    def test_release_failure_does_not_fall_back(self):
        with patch.object(generation, "urlopen", side_effect=OSError("rate limited")):
            with self.assertRaisesRegex(OSError, "rate limited"):
                generation.latest_release()

    def test_missing_yaml_does_not_download(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(generation, "urlopen") as fetch:
            with self.assertRaisesRegex(ValueError, "YAML"):
                generation.generate(Path(temporary))
            fetch.assert_not_called()

    def test_generation_stages_inputs_and_reports_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "Player.yml").write_text("game: Pathogenic\n")
            (directory / "pathogenic.apworld").write_bytes(b"world")
            runtime = directory / ".multiworldgg-0.7.273"
            (runtime / "custom_worlds").mkdir(parents=True)
            (runtime / "custom_worlds/old.apworld").write_bytes(b"stale")

            def run(command, **kwargs):
                self.assertEqual((runtime / "custom_worlds/pathogenic.apworld").read_bytes(), b"world")
                self.assertFalse((runtime / "custom_worlds/old.apworld").exists())
                self.assertTrue(kwargs["check"])
                if command[1] == "Generate.py":
                    players = Path(command[command.index("--player_files_path") + 1])
                    self.assertTrue((players / "Player.yml").is_file())
                    (directory / "output/AP_test.zip").write_bytes(b"generated")

            with patch.object(generation, "latest_release", return_value="0.7.273") as latest, \
                    patch.object(generation, "prepare_runtime", return_value=runtime), \
                    patch.object(generation.subprocess, "run", side_effect=run) as process:
                archive = generation.generate(directory)
            latest.assert_called_once()
            self.assertEqual(process.call_count, 2)
            self.assertEqual(archive.name, "AP_test.zip")
            self.assertEqual(json.loads((directory / "output/generation.json").read_text()),
                             {"release": "0.7.273", "archive": "AP_test.zip"})

    def test_dependency_failure_is_not_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "Player.yaml").write_text("game: Pathogenic")
            runtime = directory / "runtime"
            runtime.mkdir()
            with patch.object(generation, "latest_release", return_value="0.7.273"), \
                    patch.object(generation, "prepare_runtime", return_value=runtime), \
                    patch.object(generation.subprocess, "run",
                                 side_effect=subprocess.CalledProcessError(1, "ModuleUpdate.py")):
                with self.assertRaises(subprocess.CalledProcessError):
                    generation.generate(directory)
            self.assertFalse((directory / "output/generation.json").exists())

    def test_missing_output_or_generator_failure_is_not_success(self):
        for failure in (None, subprocess.CalledProcessError(1, "Generate.py")):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                (directory / "Player.yaml").write_text("game: Pathogenic")
                runtime = directory / "runtime"
                runtime.mkdir()
                (directory / "output").mkdir()
                old_archive = directory / "output/AP_old.zip"
                old_archive.write_bytes(b"old")

                def run(command, **kwargs):
                    if command[1] == "Generate.py" and failure is not None:
                        raise failure

                with patch.object(generation, "latest_release", return_value="0.7.273"), \
                        patch.object(generation, "prepare_runtime", return_value=runtime), \
                        patch.object(generation.subprocess, "run", side_effect=run):
                    with self.assertRaises(subprocess.CalledProcessError if failure else ValueError):
                        generation.generate(directory)
                self.assertEqual(old_archive.read_bytes(), b"old")
                self.assertFalse((directory / "output/generation.json").exists())

    def test_incomplete_and_symlinked_runtimes_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            runtime = directory / ".multiworldgg-0.7.273"
            runtime.mkdir()
            with self.assertRaisesRegex(ValueError, "Incomplete"):
                generation.prepare_runtime(directory, "0.7.273")
            runtime.rmdir()
            runtime.symlink_to(directory, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symlink"):
                generation.prepare_runtime(directory, "0.7.273")

    def test_archive_path_traversal_is_rejected(self):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w:gz") as archive:
            member = tarfile.TarInfo("../escaped.py")
            member.size = 1
            archive.addfile(member, io.BytesIO(b"x"))
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(generation, "urlopen", return_value=io.BytesIO(data.getvalue())):
                with self.assertRaises(tarfile.TarError):
                    generation.prepare_runtime(Path(temporary), "0.7.273")
            self.assertFalse((Path(temporary) / ".multiworldgg-0.7.273").exists())


if __name__ == "__main__":
    unittest.main()
