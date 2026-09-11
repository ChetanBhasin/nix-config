from __future__ import annotations

import tempfile
import unittest
from collections.abc import Generator
from contextlib import contextmanager
from dataclasses import dataclass, replace
from pathlib import Path

from pi_config import (  # pyright: ignore[reportImplicitRelativeImport]
    PiConfigError,
    RuntimePaths,
    SyncEngine,
)

STORE_TARGET = "/nix/store/pi-config-test-target"


@dataclass(frozen=True)
class Fixture:
    home: Path
    project: Path
    runtime: Path
    engine: SyncEngine


@contextmanager
def fixture(*, project_in_home: bool = False) -> Generator[Fixture, None, None]:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        home = root / "home"
        project = home if project_in_home else root / "project"
        runtime = home / ".pi" / "agent"
        state = root / "state"
        temp = root / "tmp"
        npm_cache = root / "npm-cache"
        for path in (runtime, project, state, temp, npm_cache):
            path.mkdir(parents=True, exist_ok=True)
        paths = RuntimePaths(
            home=home,
            cwd=project,
            state=state,
            temp=temp,
            npm_cache=npm_cache,
        )
        yield Fixture(home, project, runtime, SyncEngine(paths, env={}))


def add_store_link(root: Path) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    link = root / "store-entry"
    link.symlink_to(STORE_TARGET)
    return link


class MutableRealizationPolicyTests(unittest.TestCase):
    def test_activation_allows_global_realization_entries(self) -> None:
        with fixture() as test:
            for root in (
                test.runtime / "bin",
                test.runtime / "npm",
                test.runtime / "git",
            ):
                _ = add_store_link(root)

            self.assertEqual(test.engine.activation_preflight(), [])

    def test_activation_rejects_non_directory_realization_roots(self) -> None:
        with fixture() as test:
            for package_root in (test.runtime / "bin", test.runtime / "npm"):
                with self.subTest(package_root=package_root):
                    if package_root.name == "bin":
                        package_root.touch()
                    else:
                        external = test.home.parent / "external-npm"
                        external.mkdir()
                        package_root.symlink_to(external, target_is_directory=True)

                    self.assertIn(
                        f"mutable realization root is not a real directory: {package_root}",
                        test.engine.activation_preflight(),
                    )

    def test_activation_does_not_inherit_project_scope(self) -> None:
        with fixture(project_in_home=True) as test:
            link = add_store_link(test.home / ".pi" / "npm")

            self.assertIn(
                f"store-linked Pi path: {link}",
                test.engine.activation_preflight(),
            )

    def test_activation_rejects_store_links_in_managed_state(self) -> None:
        with fixture() as test:
            direct = test.runtime / "settings.json"
            direct.symlink_to(STORE_TARGET)
            intermediary = test.home.parent / "absolute-store-link"
            intermediary.symlink_to(STORE_TARGET)
            extension_root = test.runtime / "extensions"
            extension_root.mkdir()
            indirect = extension_root / "indirect"
            indirect.symlink_to(intermediary)

            problems = test.engine.activation_preflight()
            self.assertIn(f"store-linked Pi path: {direct}", problems)
            self.assertIn(f"store-linked Pi path: {indirect}", problems)

    def test_doctor_allows_global_and_project_realization_entries(self) -> None:
        with fixture() as test:
            for root in (
                test.runtime / "bin",
                test.runtime / "npm",
                test.runtime / "git",
                test.project / ".pi" / "npm",
                test.project / ".pi" / "git",
            ):
                _ = add_store_link(root)

            self.assertEqual(test.engine.doctor(), [])

            forbidden = add_store_link(test.project / ".pi" / "prompts")
            self.assertIn(f"store-linked path: {forbidden}", test.engine.doctor())

    def test_doctor_rejects_realization_root_symlinks(self) -> None:
        with fixture() as test:
            roots = (
                (test.runtime / "npm", test.home.parent / "global-packages"),
                (
                    test.project / ".pi" / "git",
                    test.home.parent / "project-packages",
                ),
            )
            for package_root, external in roots:
                package_root.parent.mkdir(parents=True, exist_ok=True)
                external.mkdir()
                package_root.symlink_to(external, target_is_directory=True)

            problems = test.engine.doctor()
            for package_root, _external in roots:
                self.assertIn(
                    f"mutable realization root is not a real directory: {package_root}",
                    problems,
                )

    def test_doctor_rejects_indirect_store_link_in_managed_state(self) -> None:
        with fixture() as test:
            intermediary = test.home.parent / "absolute-store-link"
            intermediary.symlink_to(STORE_TARGET)
            prompt_root = test.project / ".pi" / "prompts"
            prompt_root.mkdir(parents=True)
            indirect = prompt_root / "indirect"
            indirect.symlink_to(intermediary)

            self.assertIn(
                f"store-linked path: {indirect}",
                test.engine.doctor(),
            )


class SubagentProfileSyncTests(unittest.TestCase):
    def test_profile_capture_apply_and_deletion_preserve_local_state(self) -> None:
        with fixture() as test:
            profiles = test.runtime / "profiles" / "pi-subagents"
            profiles.mkdir(parents=True)
            for name in ("simple", "complex", "max"):
                _ = (profiles / f"{name}.json").write_text(
                    '{"subagents":{"agentOverrides":{}}}\n'
                )
            settings = test.runtime / "settings.json"
            _ = settings.write_text('{"theme":"dark"}\n')
            private = test.runtime / "models-store.json"
            _ = private.write_text('{"machine-local":"untouched"}\n')
            config = test.project / "home" / "pi" / "config"
            captured = test.engine.capture(config)
            self.assertIn("profiles", captured.changed)
            self.assertFalse((config / "models-store.json").exists())
            snapshot_profiles = config / "profiles" / "pi-subagents"
            self.assertEqual(
                sorted(path.name for path in snapshot_profiles.iterdir()),
                ["complex.json", "max.json", "simple.json"],
            )
            engine = SyncEngine(
                replace(test.engine.paths, snapshot=config), env={}
            )
            _ = engine.apply()
            _ = (snapshot_profiles / "complex.json").write_text(
                '{"subagents":{"defaultThinking":"high","agentOverrides":{}}}\n'
            )
            (snapshot_profiles / "simple.json").unlink()
            applied = engine.apply()
            self.assertIn("profiles", applied.changed)
            self.assertEqual(
                (profiles / "complex.json").read_text(),
                (snapshot_profiles / "complex.json").read_text(),
            )
            self.assertFalse((profiles / "simple.json").exists())
            self.assertEqual(private.read_text(), '{"machine-local":"untouched"}\n')
            self.assertIn('"dark"', settings.read_text())

    def test_profile_capture_rejects_symlinks_without_changing_target(self) -> None:
        with fixture() as test:
            profiles = test.runtime / "profiles"
            profiles.mkdir()
            (profiles / "alias").symlink_to(test.project, target_is_directory=True)
            config = test.project / "config"
            with self.assertRaises(PiConfigError):
                _ = test.engine.capture(config)
            self.assertFalse(config.exists())



if __name__ == "__main__":
    _ = unittest.main()
