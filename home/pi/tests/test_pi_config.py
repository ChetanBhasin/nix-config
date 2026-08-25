from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

MODULE_PATH = Path(__file__).resolve().parents[1] / "pi_config.py"
SPEC = importlib.util.spec_from_file_location("pi_config", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
pc = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = pc
SPEC.loader.exec_module(pc)


def file_entry(text: str, mode: int = 0o644):
    data = text.encode()
    return pc.Entry("file", mode, file=pc.FileData(data, mode))


def projection(**entries):
    return pc.Projection(entries)


class MatrixTests(unittest.TestCase):
    def test_apply_full_three_way_matrix(self):
        base = projection(**{"AGENTS.md": file_entry("base")})
        cases = (
            ("base", "base", "equal", (), ()),
            ("flake", "base", "flake-only", ("AGENTS.md",), ()),
            ("base", "runtime", "runtime-only", (), ("AGENTS.md",)),
            ("same", "same", "equal", (), ()),
            ("flake", "runtime", "conflict", (), ("AGENTS.md",)),
        )
        for flake, runtime, state, replacements, unresolved in cases:
            with self.subTest(flake=flake, runtime=runtime):
                plan = pc.build_plan(
                    "apply",
                    projection(**{"AGENTS.md": file_entry(flake)}),
                    projection(**{"AGENTS.md": file_entry(runtime)}),
                    base,
                    None,
                    take_source=False,
                )
                self.assertEqual(plan.states["AGENTS.md"], state)
                self.assertEqual(plan.replacements, replacements)
                self.assertEqual(plan.unresolved, unresolved)

    def test_capture_full_three_way_matrix(self):
        base = projection(**{"AGENTS.md": file_entry("base")})
        cases = (
            ("base", "base", "equal", (), ()),
            ("runtime", "base", "runtime-only", ("AGENTS.md",), ()),
            ("base", "flake", "flake-only", (), ("AGENTS.md",)),
            ("same", "same", "equal", (), ()),
            ("runtime", "flake", "conflict", (), ("AGENTS.md",)),
        )
        for runtime, flake, state, replacements, unresolved in cases:
            with self.subTest(runtime=runtime, flake=flake):
                plan = pc.build_plan(
                    "capture",
                    projection(**{"AGENTS.md": file_entry(runtime)}),
                    projection(**{"AGENTS.md": file_entry(flake)}),
                    base,
                    None,
                    take_source=False,
                )
                self.assertEqual(plan.states["AGENTS.md"], state)
                self.assertEqual(plan.replacements, replacements)
                self.assertEqual(plan.unresolved, unresolved)

    def test_take_resolves_conflicts_but_not_opposite_one_sided_changes(self):
        base = projection(
            **{
                "AGENTS.md": file_entry("base"),
                "SYSTEM.md": file_entry("base"),
            }
        )
        plan = pc.build_plan(
            "apply",
            projection(
                **{"AGENTS.md": file_entry("flake"), "SYSTEM.md": file_entry("base")}
            ),
            projection(
                **{
                    "AGENTS.md": file_entry("runtime"),
                    "SYSTEM.md": file_entry("runtime"),
                }
            ),
            base,
            None,
            take_source=True,
        )
        self.assertIn("AGENTS.md", plan.replacements)
        self.assertEqual(plan.states["AGENTS.md"], "conflict")
        self.assertEqual(plan.states["SYSTEM.md"], "runtime-only")
        self.assertEqual(plan.unresolved, ("SYSTEM.md",))

    def test_absence_is_a_deletion_in_both_directions(self):
        base = projection(**{"AGENTS.md": file_entry("old")})
        apply = pc.build_plan(
            "apply", projection(), base, base, None, take_source=False
        )
        capture = pc.build_plan(
            "capture", projection(), base, base, None, take_source=False
        )
        self.assertEqual(apply.states["AGENTS.md"], "flake-only")
        self.assertEqual(capture.states["AGENTS.md"], "runtime-only")
        self.assertEqual(apply.replacements, ("AGENTS.md",))
        self.assertEqual(capture.replacements, ("AGENTS.md",))


class PiTestBase(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.cwd = self.root / "project"
        self.snapshot = self.root / "snapshot"
        self.state = self.root / "state/pi-nix-sync"
        self.temp = self.root / "tmp"
        self.npm = self.root / "npm-cache"
        for path in (self.home, self.cwd, self.snapshot, self.temp, self.npm):
            path.mkdir(parents=True)

    def tearDown(self):
        self.temporary.cleanup()

    @property
    def runtime(self):
        return self.home / ".pi/agent"

    def engine(
        self,
        *,
        snapshot=None,
        state=None,
        env=None,
        uid=None,
        access=os.access,
        failure_hook=pc._no_failure,
        precommit_hook=pc._no_precommit,
        durability_hook=pc._no_durability_hook,
    ):
        paths = pc.RuntimePaths(
            self.home,
            self.cwd,
            snapshot=self.snapshot if snapshot is None else snapshot,
            state=self.state if state is None else state,
            temp=self.temp,
            npm_cache=self.npm,
        )
        return pc.SyncEngine(
            paths,
            env={} if env is None else env,
            uid=uid,
            access=access,
            failure_hook=failure_hook,
            precommit_hook=precommit_hook,
            durability_hook=durability_hook,
        )

    def write_file(self, root: Path, name: str, text: str, mode=0o644):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        path.chmod(mode)
        return path

    def write_json(self, root: Path, name: str, value):
        return self.write_file(root, name, json.dumps(value, indent=2) + "\n")

    def make_base(self, name: str, source: Path):
        self.state.mkdir(parents=True, exist_ok=True)
        pc.materialize_projection(
            pc.read_projection(source), self.state / name, marker=True
        )

    def capture_config(self):
        config = self.root / "flake/home/pi/config"
        config.mkdir(parents=True)
        self.write_file(config, ".gitkeep", "")
        return config


class EngineTests(PiTestBase):
    def test_first_apply_accepts_empty_runtime(self):
        self.write_file(self.snapshot, "AGENTS.md", "portable")
        result = self.engine().apply()
        self.assertEqual((self.runtime / "AGENTS.md").read_text(), "portable")
        self.assertEqual(result.changed, ("AGENTS.md",))
        self.assertTrue((self.state / "applied-base/.initialized").is_file())

    def test_first_capture_accepts_empty_portable_projection(self):
        self.write_file(self.runtime, "SYSTEM.md", "runtime")
        config = self.capture_config()
        result = self.engine().capture(config)
        self.assertEqual((config / "SYSTEM.md").read_text(), "runtime")
        self.assertEqual(result.changed, ("SYSTEM.md",))
        self.assertTrue((self.state / "capture-base/.initialized").is_file())

    def test_first_apply_existing_difference_refuses_then_take_flake_wins(self):
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        self.write_file(self.runtime, "AGENTS.md", "runtime")
        with self.assertRaises(pc.SyncConflict):
            self.engine().apply()
        self.assertEqual((self.runtime / "AGENTS.md").read_text(), "runtime")
        self.assertEqual((self.snapshot / "AGENTS.md").read_text(), "flake")
        self.assertFalse(self.state.exists())
        result = self.engine().apply(take_flake=True)
        self.assertEqual(result.changed, ("AGENTS.md",))
        self.assertEqual((self.runtime / "AGENTS.md").read_text(), "flake")

    def test_first_capture_existing_difference_refuses_then_take_runtime_wins(self):
        config = self.capture_config()
        self.write_file(config, "AGENTS.md", "flake")
        self.write_file(self.runtime, "AGENTS.md", "runtime")
        with self.assertRaises(pc.SyncConflict):
            self.engine().capture(config)
        self.assertEqual((config / "AGENTS.md").read_text(), "flake")
        self.assertEqual((self.runtime / "AGENTS.md").read_text(), "runtime")
        self.assertFalse(self.state.exists())
        result = self.engine().capture(config, take_runtime=True)
        self.assertEqual(result.changed, ("AGENTS.md",))
        self.assertEqual((config / "AGENTS.md").read_text(), "runtime")

    def test_cross_seed_allows_change_when_other_base_matches_target(self):
        self.write_file(self.runtime, "AGENTS.md", "base")
        self.make_base("capture-base", self.runtime)
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        self.engine().apply()
        self.assertEqual((self.runtime / "AGENTS.md").read_text(), "flake")

    def test_cross_seed_refuses_opposite_direction_change(self):
        self.write_file(self.snapshot, "AGENTS.md", "base")
        self.make_base("capture-base", self.snapshot)
        self.write_file(self.runtime, "AGENTS.md", "runtime")
        with self.assertRaises(pc.SyncConflict):
            self.engine().apply(take_flake=True)
        self.assertEqual((self.runtime / "AGENTS.md").read_text(), "runtime")

    def test_apply_deletion_preserves_unmanaged_files(self):
        self.write_file(self.runtime, "AGENTS.md", "old")
        self.write_file(self.runtime, "auth.json", "machine secret")
        self.make_base("applied-base", self.runtime)
        self.engine().apply()
        self.assertFalse((self.runtime / "AGENTS.md").exists())
        self.assertEqual((self.runtime / "auth.json").read_text(), "machine secret")

    def test_capture_deletion_preserves_gitkeep_and_unmanaged_file(self):
        config = self.capture_config()
        self.write_file(config, "AGENTS.md", "old")
        self.write_file(config, "README.local", "unmanaged")
        self.make_base("capture-base", config)
        self.engine().capture(config)
        self.assertFalse((config / "AGENTS.md").exists())
        self.assertTrue((config / ".gitkeep").exists())
        self.assertEqual((config / "README.local").read_text(), "unmanaged")

    def test_whole_directory_replacement_removes_stale_children(self):
        self.write_file(self.snapshot, "prompts/current.md", "new")
        self.write_file(self.runtime, "prompts/current.md", "old")
        self.write_file(self.runtime, "prompts/stale.md", "stale")
        base_root = self.root / "base"
        self.write_file(base_root, "prompts/current.md", "old")
        self.write_file(base_root, "prompts/stale.md", "stale")
        self.make_base("applied-base", base_root)
        self.engine().apply()
        self.assertEqual((self.runtime / "prompts/current.md").read_text(), "new")
        self.assertFalse((self.runtime / "prompts/stale.md").exists())

    def test_conflict_causes_no_managed_target_mutation(self):
        base_root = self.root / "base"
        self.write_file(base_root, "AGENTS.md", "base")
        self.make_base("applied-base", base_root)
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        self.write_file(self.runtime, "AGENTS.md", "runtime")
        before = (self.runtime / "AGENTS.md").read_bytes()
        with self.assertRaises(pc.SyncConflict):
            self.engine().apply()
        self.assertEqual((self.runtime / "AGENTS.md").read_bytes(), before)

    def test_identical_changes_advance_base_without_rewriting_target(self):
        base_root = self.root / "base"
        self.write_file(base_root, "AGENTS.md", "old")
        self.make_base("applied-base", base_root)
        self.write_file(self.snapshot, "AGENTS.md", "same new")
        target = self.write_file(self.runtime, "AGENTS.md", "same new")
        inode = target.stat().st_ino
        result = self.engine().apply()
        self.assertEqual(result.changed, ())
        self.assertEqual(target.stat().st_ino, inode)
        applied = pc.load_baseline(self.state / "applied-base")
        self.assertTrue(
            pc.projections_equal(applied, pc.read_projection(self.snapshot))
        )

    def test_transaction_failure_rolls_back_target_and_base_and_keeps_backup(self):
        base_root = self.root / "base"
        self.write_file(base_root, "AGENTS.md", "base")
        self.make_base("applied-base", base_root)
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        self.write_file(self.runtime, "AGENTS.md", "base")

        def fail(phase, _name):
            if phase == "after_base":
                raise RuntimeError("injected failure")

        with self.assertRaises(pc.TransactionFailure):
            self.engine(failure_hook=fail).apply()
        self.assertEqual((self.runtime / "AGENTS.md").read_text(), "base")
        restored = pc.load_baseline(self.state / "applied-base")
        self.assertTrue(pc.projections_equal(restored, pc.read_projection(base_root)))
        self.assertFalse((self.state / "transaction.json").exists())
        backups = list((self.state / "backups").iterdir())
        self.assertEqual(len(backups), 1)
        self.assertRegex(backups[0].name, r"^\d{8}T\d{6}\.\d{6}Z-apply-")
        self.assertEqual((backups[0] / "target/AGENTS.md").read_text(), "base")
        self.assertTrue((backups[0] / "baseline/.initialized").is_file())

    def _assert_failure_phase_rolls_back(self, phase):
        base_root = self.root / f"base-{phase}"
        self.write_file(base_root, "AGENTS.md", "base")
        self.make_base("applied-base", base_root)
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        self.write_file(self.runtime, "AGENTS.md", "base")

        def fail(current_phase, _name):
            if current_phase == phase:
                raise RuntimeError(f"failure at {phase}")

        with self.assertRaises(pc.TransactionFailure):
            self.engine(failure_hook=fail).apply()
        self.assertEqual((self.runtime / "AGENTS.md").read_text(), "base")
        restored = pc.load_baseline(self.state / "applied-base")
        self.assertTrue(pc.projections_equal(restored, pc.read_projection(base_root)))
        self.assertFalse((self.state / "transaction.json").exists())

    def test_after_target_failure_rolls_back_before_base(self):
        self._assert_failure_phase_rolls_back("after_target")

    def test_before_base_failure_rolls_back_target(self):
        self._assert_failure_phase_rolls_back("before_base")

    def test_success_fsyncs_staging_backup_journal_target_and_base(self):
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        phases = []

        def durable(phase, _path):
            phases.append(phase)

        self.engine(durability_hook=durable).apply()
        self.assertTrue(
            {
                "staged-target",
                "staged-base",
                "backup",
                "journal-installed",
                "installed-target-entry",
                "installed-target",
                "installed-base",
                "journal-removed",
            }.issubset(phases)
        )

    def test_precommit_pi_lock_refuses_before_journal_or_managed_mutation(self):
        self.write_file(self.snapshot, "AGENTS.md", "flake")

        def start_pi():
            (self.runtime / "active.lock").mkdir(parents=True)

        with self.assertRaises(pc.TransactionFailure):
            self.engine(precommit_hook=start_pi).apply()
        self.assertFalse((self.runtime / "AGENTS.md").exists())
        self.assertFalse((self.state / "applied-base").exists())
        self.assertFalse((self.state / "transaction.json").exists())

    def test_precommit_source_change_refuses_before_target_or_base_mutation(self):
        self.write_file(self.snapshot, "AGENTS.md", "flake")

        def change_source():
            self.write_file(self.snapshot, "AGENTS.md", "changed during staging")

        with self.assertRaisesRegex(pc.TransactionFailure, "inputs changed"):
            self.engine(precommit_hook=change_source).apply()
        self.assertFalse(self.runtime.exists())
        self.assertFalse((self.state / "applied-base").exists())

    def test_precommit_capture_target_change_is_not_overwritten(self):
        config = self.capture_config()
        self.write_file(self.runtime, "AGENTS.md", "runtime")

        def change_target():
            self.write_file(config, "AGENTS.md", "changed during staging")

        with self.assertRaisesRegex(pc.TransactionFailure, "inputs changed"):
            self.engine(precommit_hook=change_target).capture(config)
        self.assertEqual((config / "AGENTS.md").read_text(), "changed during staging")
        self.assertFalse((self.state / "capture-base").exists())

    def test_pending_journal_blocks_mutation(self):
        self.state.mkdir(parents=True)
        (self.state / "transaction.json").write_text("{}\n")
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        with self.assertRaisesRegex(pc.PiConfigError, "pending transaction journal"):
            self.engine().apply()
        self.assertFalse(self.runtime.exists())

    def test_pending_journal_blocks_read_only_sync_without_changing_it(self):
        self.state.mkdir(parents=True)
        journal = self.state / "transaction.json"
        journal.write_text('{"pending": true}\n')
        with self.assertRaisesRegex(pc.PiConfigError, "pending transaction journal"):
            self.engine().status()
        with self.assertRaisesRegex(pc.PiConfigError, "pending transaction journal"):
            self.engine().diff()
        self.assertEqual(journal.read_text(), '{"pending": true}\n')

    def test_settings_comparison_is_semantic_and_ignores_runtime_keys(self):
        self.write_file(self.snapshot, "settings.json", '{"b": 2, "a": 1}\n')
        self.write_file(
            self.runtime,
            "settings.json",
            '{\n  "trackingId": "local", "a": 1, "lastChangelogVersion": "9", "b": 2\n}\n',
        )
        status = self.engine().status()
        self.assertEqual(status.apply.states["settings.json"], "equal")
        self.assertEqual(status.capture.states["settings.json"], "equal")

    def test_keybindings_and_models_comparison_is_semantic(self):
        self.write_file(self.snapshot, "keybindings.json", '{"b": 2, "a": 1}\n')
        self.write_file(self.runtime, "keybindings.json", '{\n "a": 1, "b": 2\n}\n')
        self.write_file(self.snapshot, "models.json", '{"model": {"maxTokens": 4}}\n')
        self.write_file(self.runtime, "models.json", '{\n"model":{"maxTokens":4}\n}\n')
        status = self.engine().status()
        for name in ("keybindings.json", "models.json"):
            self.assertEqual(status.apply.states[name], "equal")
            self.assertEqual(status.capture.states[name], "equal")

    def test_keybindings_and_models_require_json_objects(self):
        for name in ("keybindings.json", "models.json"):
            with self.subTest(name=name):
                self.write_file(self.snapshot, name, "[]\n")
                with self.assertRaisesRegex(pc.PiConfigError, "JSON object"):
                    pc.read_projection(self.snapshot)
                (self.snapshot / name).unlink()

    def test_capture_canonicalizes_keybindings_and_models(self):
        config = self.capture_config()
        self.write_file(self.runtime, "keybindings.json", '{"z": 1, "a": 2}\n')
        self.write_file(self.runtime, "models.json", '{"z": {}, "a": {}}\n')
        self.engine().capture(config)
        self.assertEqual(
            (config / "keybindings.json").read_text(),
            '{\n  "a": 2,\n  "z": 1\n}\n',
        )
        self.assertEqual(
            (config / "models.json").read_text(),
            '{\n  "a": {},\n  "z": {}\n}\n',
        )

    def test_apply_replaces_portable_settings_and_preserves_runtime_only_keys(self):
        self.write_json(
            self.snapshot, "settings.json", {"theme": "new", "packages": ["one"]}
        )
        self.write_json(
            self.runtime,
            "settings.json",
            {"theme": "old", "trackingId": "track", "lastChangelogVersion": "0.84.2"},
        )
        base_root = self.root / "base"
        self.write_json(base_root, "settings.json", {"theme": "old"})
        self.make_base("applied-base", base_root)
        self.engine().apply()
        value = json.loads((self.runtime / "settings.json").read_text())
        self.assertEqual(
            value,
            {
                "theme": "new",
                "packages": ["one"],
                "trackingId": "track",
                "lastChangelogVersion": "0.84.2",
            },
        )

    def test_apply_portable_settings_deletion_keeps_runtime_only_file(self):
        self.write_json(
            self.runtime,
            "settings.json",
            {"theme": "old", "trackingId": "track", "lastChangelogVersion": "0.84.2"},
        )
        base_root = self.root / "base"
        self.write_json(base_root, "settings.json", {"theme": "old"})
        self.make_base("applied-base", base_root)
        self.engine().apply()
        value = json.loads((self.runtime / "settings.json").read_text())
        self.assertEqual(
            value, {"trackingId": "track", "lastChangelogVersion": "0.84.2"}
        )

    def test_capture_strips_runtime_only_settings_but_keeps_packages(self):
        config = self.capture_config()
        self.write_json(
            self.runtime,
            "settings.json",
            {
                "packages": ["pkg"],
                "trackingId": "track",
                "lastChangelogVersion": "0.84.2",
            },
        )
        self.engine().capture(config)
        self.assertEqual(
            json.loads((config / "settings.json").read_text()), {"packages": ["pkg"]}
        )

    def test_runtime_only_settings_do_not_create_portable_settings(self):
        config = self.capture_config()
        self.write_json(
            self.runtime,
            "settings.json",
            {"trackingId": "track", "lastChangelogVersion": "0.84.2"},
        )
        self.engine().capture(config)
        self.assertFalse((config / "settings.json").exists())

    def test_capture_excludes_machine_local_generated_and_session_trees(self):
        config = self.capture_config()
        self.write_json(
            self.runtime, "settings.json", {"packages": ["npm:portable-package"]}
        )
        for name in (
            "auth.json",
            "trust.json",
            "sessions/session.json",
            "npm/cache",
            "git/checkout",
            "logs/pi.log",
            "tools/bin",
        ):
            self.write_file(self.runtime, name, "machine-local")
        self.engine().capture(config)
        self.assertEqual(
            json.loads((config / "settings.json").read_text()),
            {"packages": ["npm:portable-package"]},
        )
        for name in (
            "auth.json",
            "trust.json",
            "sessions",
            "npm",
            "git",
            "logs",
            "tools",
        ):
            self.assertFalse((config / name).exists())

    def test_models_reject_literal_secrets_without_max_tokens_false_positive(self):
        self.write_json(
            self.snapshot,
            "models.json",
            {"provider": {"apiKey": "literal", "maxTokens": 4096}},
        )
        with self.assertRaisesRegex(pc.PiConfigError, "literal secret"):
            self.engine().status()
        self.write_json(
            self.snapshot,
            "models.json",
            {"provider": {"apiKey": "$API_KEY", "maxTokens": 4096}},
        )
        pc.read_projection(self.snapshot)

    def test_models_allow_environment_and_command_references(self):
        self.write_json(
            self.snapshot,
            "models.json",
            {
                "one": {"api-key": "${API_KEY}", "maxTokens": 1024},
                "two": {"authentication": "!security find-generic-password -w"},
                "three": {"headers": {"Authorization": "$AUTH_HEADER"}},
            },
        )
        pc.read_projection(self.snapshot)

    def test_models_reject_prefixed_auth_headers_and_allow_references(self):
        for header in ("X-Auth-Token", "X-Goog-Api-Key"):
            with self.subTest(header=header):
                self.write_json(
                    self.snapshot,
                    "models.json",
                    {"provider": {"headers": {header: "literal-secret"}}},
                )
                with self.assertRaisesRegex(pc.PiConfigError, "literal secret"):
                    pc.read_projection(self.snapshot)
        self.write_json(
            self.snapshot,
            "models.json",
            {
                "provider": {
                    "headers": {
                        "X-Auth-Token": "$AUTH_TOKEN",
                        "X-Goog-Api-Key": "!security find-generic-password -w",
                    },
                    "maxTokens": 8192,
                }
            },
        )
        pc.read_projection(self.snapshot)

    def test_top_level_and_nested_symlinks_are_rejected(self):
        target = self.root / "outside"
        target.write_text("outside")
        (self.snapshot / "AGENTS.md").symlink_to(target)
        with self.assertRaisesRegex(pc.PiConfigError, "symlink"):
            pc.read_projection(self.snapshot)
        (self.snapshot / "AGENTS.md").unlink()
        (self.snapshot / "skills").mkdir()
        (self.snapshot / "skills/link").symlink_to(target)
        with self.assertRaisesRegex(pc.PiConfigError, "symlinks"):
            pc.read_projection(self.snapshot)

    @unittest.skipUnless(hasattr(os, "mkfifo"), "requires POSIX FIFOs")
    def test_special_files_are_rejected(self):
        (self.snapshot / "skills").mkdir()
        os.mkfifo(self.snapshot / "skills/pipe")
        with self.assertRaisesRegex(pc.PiConfigError, "regular files and directories"):
            pc.read_projection(self.snapshot)

    def test_executable_bits_survive_apply_and_owner_write_is_added(self):
        script = self.write_file(self.snapshot, "extensions/tool", "#!/bin/sh\n", 0o555)
        self.assertTrue(script.stat().st_mode & stat.S_IXUSR)
        self.engine().apply()
        installed_mode = stat.S_IMODE((self.runtime / "extensions/tool").stat().st_mode)
        self.assertTrue(installed_mode & stat.S_IXUSR)
        self.assertTrue(installed_mode & stat.S_IWUSR)

    def test_executable_bits_survive_capture(self):
        config = self.capture_config()
        self.write_file(self.runtime, "skills/tool/run", "#!/bin/sh\n", 0o700)
        self.engine().capture(config)
        captured_mode = stat.S_IMODE((config / "skills/tool/run").stat().st_mode)
        self.assertTrue(captured_mode & stat.S_IXUSR)
        self.assertTrue(captured_mode & stat.S_IWUSR)

    def test_pi_runtime_lock_blocks_apply(self):
        (self.runtime / "nested/active.lock").mkdir(parents=True)
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        with self.assertRaisesRegex(pc.PiConfigError, "exit Pi"):
            self.engine().apply()

    def test_status_and_diff_refuse_pi_lock_without_creating_state(self):
        (self.runtime / "active.lock").mkdir(parents=True)
        for operation in (self.engine().status, self.engine().diff):
            with (
                self.subTest(operation=operation.__name__),
                self.assertRaisesRegex(pc.PiConfigError, "exit Pi"),
            ):
                operation()
        self.assertFalse(self.state.exists())

    def test_project_lock_blocks_capture(self):
        (self.cwd / ".pi/packages/install.lock").mkdir(parents=True)
        self.write_file(self.runtime, "AGENTS.md", "runtime")
        with self.assertRaisesRegex(pc.PiConfigError, "exit Pi"):
            self.engine().capture(self.capture_config())

    def test_nonblocking_cli_lock_contention(self):
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        with (
            pc.CliLock(self.state / "cli.lock"),
            self.assertRaisesRegex(pc.PiConfigError, "another pi-config mutation"),
        ):
            self.engine().apply()

    def test_status_and_diff_never_create_state(self):
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        status = self.engine().status()
        output, different = self.engine().diff()
        self.assertEqual(status.apply.states["AGENTS.md"], "flake-only")
        self.assertEqual(status.capture.states["AGENTS.md"], "conflict")
        self.assertTrue(different)
        self.assertIn("flake/AGENTS.md", output)
        self.assertFalse(self.state.exists())

    def test_status_uses_both_independent_baselines(self):
        apply_base = self.root / "apply-status-base"
        capture_base = self.root / "capture-status-base"
        self.write_file(apply_base, "AGENTS.md", "runtime")
        self.write_file(capture_base, "AGENTS.md", "flake")
        self.make_base("applied-base", apply_base)
        self.make_base("capture-base", capture_base)
        self.write_file(self.runtime, "AGENTS.md", "runtime")
        self.write_file(self.snapshot, "AGENTS.md", "flake")
        status = self.engine().status()
        self.assertEqual(status.apply.states["AGENTS.md"], "flake-only")
        self.assertEqual(status.capture.states["AGENTS.md"], "runtime-only")

    def test_live_nested_unwritable_managed_file_blocks_all_sync_commands(self):
        nested = self.write_file(self.runtime, "skills/nested/tool", "tool")

        def access(path, _mode):
            return Path(path) != nested

        engine = self.engine(access=access)
        operations = (
            engine.status,
            engine.diff,
            engine.apply,
            lambda: engine.capture(self.capture_config()),
        )
        for operation in operations:
            with (
                self.subTest(operation=operation),
                self.assertRaisesRegex(pc.PiConfigError, "not writable"),
            ):
                operation()
        self.assertFalse(self.state.exists())

    def test_live_store_linked_managed_file_blocks_sync_without_state(self):
        self.runtime.mkdir(parents=True)
        (self.runtime / "AGENTS.md").symlink_to("/nix/store/fake-pi/AGENTS.md")
        with self.assertRaisesRegex(pc.PiConfigError, "store-linked"):
            self.engine().status()
        self.assertFalse(self.state.exists())

    def test_redirection_is_rejected_for_all_sync_operations(self):
        engine = self.engine(env={"PI_CODING_AGENT_DIR": str(self.root / "redirect")})
        with self.assertRaisesRegex(pc.PiConfigError, "PI_CODING_AGENT_DIR"):
            engine.status()
        with self.assertRaisesRegex(pc.PiConfigError, "PI_CODING_AGENT_DIR"):
            engine.apply()
        with self.assertRaisesRegex(pc.PiConfigError, "PI_CODING_AGENT_DIR"):
            engine.capture(self.capture_config())

    def test_capture_flake_only_change_remains_unresolved_with_take_runtime(self):
        config = self.capture_config()
        self.write_file(config, "AGENTS.md", "base")
        self.write_file(self.runtime, "AGENTS.md", "base")
        self.make_base("capture-base", config)
        self.write_file(config, "AGENTS.md", "flake edit")
        with self.assertRaises(pc.SyncConflict):
            self.engine().capture(config, take_runtime=True)
        self.assertEqual((config / "AGENTS.md").read_text(), "flake edit")


class DoctorAndPreflightTests(PiTestBase):
    def test_doctor_absent_paths_is_read_only(self):
        # Remove optional paths so the check proves it does not create them.
        self.npm.rmdir()
        problems = self.engine().doctor()
        self.assertEqual(problems, [])
        self.assertFalse(self.home.joinpath(".pi").exists())
        self.assertFalse(self.home.joinpath(".agents").exists())
        self.assertFalse(self.npm.exists())

    def test_doctor_accepts_writable_partial_hierarchy(self):
        (self.home / ".pi").mkdir()
        (self.home / ".agents/skills").mkdir(parents=True)
        self.assertEqual(self.engine().doctor(), [])
        self.assertFalse(self.runtime.exists())

    def test_doctor_rejects_foreign_owned_and_unwritable_paths(self):
        (self.home / ".pi").mkdir()
        fake_uid = os.getuid() + 1000

        def access(path, mode):
            return Path(path) != self.temp

        problems = self.engine(uid=fake_uid, access=access).doctor()
        self.assertTrue(
            any("foreign-owned path" in item and ".pi" in item for item in problems)
        )
        self.assertTrue(
            any(
                "unwritable path" in item and str(self.temp) in item
                for item in problems
            )
        )

    def test_doctor_rejects_missing_temp_directory(self):
        self.temp.rmdir()
        problems = self.engine().doctor()
        self.assertIn(f"temporary directory does not exist: {self.temp}", problems)

    def test_doctor_rejects_store_linked_managed_file(self):
        self.runtime.mkdir(parents=True)
        (self.runtime / "AGENTS.md").symlink_to("/nix/store/fake-pi/AGENTS.md")
        problems = self.engine().doctor()
        self.assertTrue(
            any(
                "store-linked path" in item and "AGENTS.md" in item for item in problems
            )
        )

    def test_doctor_reports_pending_journal_without_altering_state(self):
        self.state.mkdir(parents=True)
        journal = self.state / "transaction.json"
        journal.write_bytes(b'{"operation":"apply","pending":true}\n')

        def snapshot_tree():
            return {
                str(path.relative_to(self.state)): (
                    path.lstat().st_mode,
                    path.read_bytes() if path.is_file() else None,
                )
                for path in sorted(self.state.rglob("*"))
            }

        before = snapshot_tree()
        problems = self.engine().doctor()
        after = snapshot_tree()
        self.assertIn(
            f"pending transaction journal requires manual recovery: {journal}",
            problems,
        )
        self.assertEqual(after, before)

    def test_activation_preflight_absent_is_repeatable_and_read_only(self):
        before = sorted(
            str(path.relative_to(self.root)) for path in self.root.rglob("*")
        )
        self.assertEqual(self.engine().activation_preflight(), [])
        self.assertEqual(self.engine().activation_preflight(), [])
        after = sorted(
            str(path.relative_to(self.root)) for path in self.root.rglob("*")
        )
        self.assertEqual(after, before)
        self.assertFalse((self.home / ".pi").exists())

    def test_activation_preflight_accepts_writable_partial_pi(self):
        (self.home / ".pi").mkdir()
        self.assertEqual(self.engine().activation_preflight(), [])
        self.assertFalse(self.runtime.exists())

    def test_activation_preflight_rejects_unwritable_pi(self):
        pi = self.home / ".pi"
        pi.mkdir()

        def access(path, mode):
            return Path(path) != pi

        problems = self.engine(access=access).activation_preflight()
        self.assertIn(f"unwritable Pi path: {pi}", problems)

    def test_activation_preflight_foreign_owner_prints_exact_chown(self):
        (self.home / ".pi/agent").mkdir(parents=True)
        problems = self.engine(uid=os.getuid() + 1000).activation_preflight()
        self.assertIn('sudo chown -R "$(id -un):$(id -gn)" "$HOME/.pi"', problems)

    def test_activation_preflight_rejects_store_linked_pi(self):
        (self.home / ".pi").symlink_to("/nix/store/fake-home-manager-files/.pi")
        problems = self.engine().activation_preflight()
        self.assertTrue(any("must not be a symlink" in item for item in problems))

    def test_activation_preflight_reports_each_legacy_omp_store_link(self):
        legacy = (
            self.home / ".omp/agent/APPEND_SYSTEM.md",
            self.home / ".omp/agent/lsp.json",
            self.home / ".omp/agent/themes/gruvbox-night.json",
        )
        for index, path in enumerate(legacy):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(f"/nix/store/hash-home-manager-files/file-{index}")
        problems = self.engine().activation_preflight()
        linked = [item for item in problems if item.startswith("legacy OMP file")]
        guidance = [
            item for item in problems if item.startswith("dereference manually")
        ]
        self.assertEqual(len(linked), 3)
        self.assertEqual(len(guidance), 3)
        for path in legacy:
            self.assertTrue(path.is_symlink())
            self.assertTrue(any(str(path) in item for item in guidance))
        self.assertTrue(all("mktemp" in item for item in guidance))
        self.assertTrue(all(".pi-config-dereferenced" not in item for item in guidance))


class UtilityTests(unittest.TestCase):
    def test_discover_flake_root_walks_up_and_fails_clearly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            nested = root / "a/b"
            nested.mkdir(parents=True)
            (root / "home/pi/config").mkdir(parents=True)
            self.assertEqual(pc.discover_flake_root(nested), root.resolve())
        with (
            tempfile.TemporaryDirectory() as temporary,
            self.assertRaisesRegex(pc.PiConfigError, "--flake-root"),
        ):
            pc.discover_flake_root(Path(temporary))

    def test_gitkeep_is_ignored(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / ".gitkeep").write_text("")
            self.assertTrue(pc.read_projection(root).is_empty())

    def test_direct_cli_preflight_does_not_create_pi_or_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            work = root / "work"
            temp = root / "tmp"
            for path in (home, work, temp):
                path.mkdir()
            environment = dict(os.environ)
            environment.update(
                {
                    "HOME": str(home),
                    "TMPDIR": str(temp),
                    "npm_config_cache": str(root / "npm"),
                }
            )
            result = subprocess.run(
                [sys.executable, str(MODULE_PATH), "_activation-preflight"],
                cwd=work,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((home / ".pi").exists())
            self.assertFalse((home / ".local/state/pi-nix-sync").exists())

    def test_cli_conflict_is_one_and_unsafe_json_is_two(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            work = root / "work"
            temp = root / "tmp"
            snapshot = root / "snapshot"
            runtime = home / ".pi/agent"
            for path in (home, work, temp, snapshot, runtime):
                path.mkdir(parents=True, exist_ok=True)
            (snapshot / "AGENTS.md").write_text("flake")
            (runtime / "AGENTS.md").write_text("runtime")
            environment = dict(os.environ)
            environment.pop("PI_CODING_AGENT_DIR", None)
            environment.update(
                {
                    "HOME": str(home),
                    "TMPDIR": str(temp),
                    "npm_config_cache": str(root / "npm"),
                    "PI_CONFIG_SNAPSHOT": str(snapshot),
                    "PYTHONDONTWRITEBYTECODE": "1",
                }
            )
            conflict = subprocess.run(
                [sys.executable, str(MODULE_PATH), "apply"],
                cwd=work,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(conflict.returncode, 1, conflict.stderr)
            self.assertFalse((home / ".local/state/pi-nix-sync").exists())
            (snapshot / "AGENTS.md").unlink()
            (snapshot / "models.json").write_text("[]\n")
            invalid = subprocess.run(
                [sys.executable, str(MODULE_PATH), "status"],
                cwd=work,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(invalid.returncode, 2, invalid.stderr)

    def test_cli_status_labels_both_directions_and_returns_one_for_difference(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            work = root / "work"
            temp = root / "tmp"
            snapshot = root / "snapshot"
            for path in (home, work, temp, snapshot):
                path.mkdir(parents=True)
            (snapshot / "AGENTS.md").write_text("flake")
            environment = dict(os.environ)
            environment.pop("PI_CODING_AGENT_DIR", None)
            environment.update(
                {
                    "HOME": str(home),
                    "TMPDIR": str(temp),
                    "PI_CONFIG_SNAPSHOT": str(snapshot),
                    "PYTHONDONTWRITEBYTECODE": "1",
                }
            )
            result = subprocess.run(
                [sys.executable, str(MODULE_PATH), "status"],
                cwd=work,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("[apply: flake -> runtime]", result.stdout)
            self.assertIn("[capture: runtime -> flake]", result.stdout)
            self.assertFalse((home / ".local/state/pi-nix-sync").exists())


if __name__ == "__main__":
    unittest.main()
