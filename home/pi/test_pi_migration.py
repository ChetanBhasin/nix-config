"""Regression coverage for retiring the Codex conversion configuration."""

from __future__ import annotations

# unittest initializes instance fixtures in setUp rather than __init__.
# pyright: reportUninitializedInstanceVariable=false

import tempfile
import unittest
from pathlib import Path

from pi_config import (  # pyright: ignore[reportImplicitRelativeImport]
    RuntimePaths,
    SyncConflict,
    SyncEngine,
    materialize_projection,
    read_projection,
)

RETIRED = "pi-codex-conversion.json"
LEGACY_POLICY = '{ "voice": { "enabled": true } }\n'


class RetiredConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.runtime: Path = root / "home/.pi/agent"
        self.snapshot: Path = root / "snapshot"
        self.state: Path = root / "state"
        for directory in (self.runtime, self.snapshot):
            directory.mkdir(parents=True)
            _ = (directory / "settings.json").write_text('{"theme":"test"}\n')
        _ = (self.runtime / RETIRED).write_text(LEGACY_POLICY)
        self.engine: SyncEngine = SyncEngine(
            RuntimePaths(
                home=root / "home",
                cwd=root,
                snapshot=self.snapshot,
                state=self.state,
            ),
            env={},
        )

    def seed_baseline(self, name: str) -> None:
        materialize_projection(
            read_projection(self.runtime), self.state / name, marker=True
        )

    def test_apply_removes_baseline_managed_retired_config(self) -> None:
        self.seed_baseline("applied-base")
        result = self.engine.apply()
        self.assertIn(RETIRED, result.changed)
        self.assertFalse((self.runtime / RETIRED).exists())
        self.assertIsNotNone(result.backup)

    def test_apply_without_baseline_requires_explicit_selection(self) -> None:
        with self.assertRaises(SyncConflict):
            _ = self.engine.apply()
        self.assertEqual((self.runtime / RETIRED).read_text(), LEGACY_POLICY)
        result = self.engine.apply(force=True)
        self.assertIn(RETIRED, result.changed)
        self.assertFalse((self.runtime / RETIRED).exists())

    def test_capture_does_not_reintroduce_live_retired_config(self) -> None:
        result = self.engine.capture(self.snapshot)
        self.assertNotIn(RETIRED, result.changed)
        self.assertFalse((self.snapshot / RETIRED).exists())
        self.assertTrue((self.runtime / RETIRED).exists())
        self.assertFalse((self.state / "capture-base" / RETIRED).exists())

    def test_capture_removes_retired_config_from_old_snapshot(self) -> None:
        self.seed_baseline("capture-base")
        _ = (self.snapshot / RETIRED).write_text(LEGACY_POLICY)
        result = self.engine.capture(self.snapshot)
        self.assertIn(RETIRED, result.changed)
        self.assertFalse((self.snapshot / RETIRED).exists())
        self.assertTrue((self.runtime / RETIRED).exists())

    def test_apply_preserves_unmanaged_files(self) -> None:
        unmanaged = self.runtime / "unmanaged.json"
        _ = unmanaged.write_text('{"keep":true}\n')
        _ = self.engine.apply(force=True)
        self.assertTrue(unmanaged.exists())
        self.assertFalse((self.runtime / RETIRED).exists())


if __name__ == "__main__":
    _ = unittest.main()
