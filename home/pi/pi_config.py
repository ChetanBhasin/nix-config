#!/usr/bin/env python3
"""Synchronize Pi's portable configuration without managing Pi's live state."""

from __future__ import annotations

import argparse
import contextlib
import dataclasses
import datetime as dt
import difflib
import errno
import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Callable, Iterable, Mapping, Sequence
from pathlib import Path
from typing import Self

FILE_NAMES = (
    "settings.json",
    "keybindings.json",
    "models.json",
    "pi-codex-conversion.json",
    "AGENTS.md",
    "SYSTEM.md",
    "APPEND_SYSTEM.md",
)
DIRECTORY_NAMES = ("extensions", "skills", "prompts", "themes")
MANAGED_NAMES = FILE_NAMES + DIRECTORY_NAMES
RUNTIME_SETTING_KEYS = ("lastChangelogVersion", "trackingId")
BASE_MARKER = ".initialized"
ENV_REFERENCE = re.compile(
    r"^(?:\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*\})$"
)


class PiConfigError(RuntimeError):
    """A user-actionable synchronization error."""


class SyncConflict(PiConfigError):
    def __init__(self, operation: str, states: Mapping[str, str]):
        self.operation = operation
        self.states = dict(states)
        details = ", ".join(
            f"{name}={state}"
            for name, state in states.items()
            if state in {"conflict", "runtime-only", "flake-only"}
        )
        flag = "--take-flake" if operation == "apply" else "--take-runtime"
        super().__init__(
            f"{operation} refused: unresolved changes ({details}); inspect status/diff and use {flag} only for conflicts"
        )


class TransactionFailure(PiConfigError):
    pass


@dataclasses.dataclass(frozen=True)
class FileData:
    data: bytes
    mode: int


@dataclasses.dataclass(frozen=True)
class Entry:
    kind: str
    mode: int
    file: FileData | None = None
    directories: tuple[tuple[str, int], ...] = ()
    files: tuple[tuple[str, FileData], ...] = ()

    def digest(self) -> str:
        digest = hashlib.sha256()
        digest.update(self.kind.encode())
        digest.update(b"\0")
        digest.update(str(self.mode & 0o111).encode())
        if self.kind == "file":
            assert self.file is not None
            digest.update(b"\0")
            digest.update(str(self.file.mode & 0o111).encode())
            digest.update(b"\0")
            digest.update(self.file.data)
        else:
            for relative, mode in self.directories:
                digest.update(b"D\0")
                digest.update(relative.encode("utf-8", "surrogateescape"))
                digest.update(b"\0")
                digest.update(str(mode & 0o111).encode())
            for relative, file_data in self.files:
                digest.update(b"F\0")
                digest.update(relative.encode("utf-8", "surrogateescape"))
                digest.update(b"\0")
                digest.update(str(file_data.mode & 0o111).encode())
                digest.update(b"\0")
                digest.update(file_data.data)
        return digest.hexdigest()


@dataclasses.dataclass(frozen=True)
class Projection:
    entries: Mapping[str, Entry]

    def entry(self, name: str) -> Entry | None:
        return self.entries.get(name)

    def is_empty(self) -> bool:
        return not self.entries


@dataclasses.dataclass(frozen=True)
class SyncPlan:
    operation: str
    states: Mapping[str, str]
    replacements: tuple[str, ...]
    unresolved: tuple[str, ...]
    source: Projection


@dataclasses.dataclass(frozen=True)
class SyncResult:
    operation: str
    states: Mapping[str, str]
    changed: tuple[str, ...]
    backup: Path | None


@dataclasses.dataclass(frozen=True)
class SyncStatus:
    apply: SyncPlan
    capture: SyncPlan


@dataclasses.dataclass(frozen=True)
class OperationView:
    plan: SyncPlan
    target: Projection
    baseline: Projection | None
    other_baseline: Projection | None
    desired_target: Projection


@dataclasses.dataclass(frozen=True)
class RuntimePaths:
    home: Path
    cwd: Path
    snapshot: Path | None = None
    state: Path | None = None
    temp: Path | None = None
    npm_cache: Path | None = None

    def __post_init__(self) -> None:
        if self.state is None:
            object.__setattr__(self, "state", self.home / ".local/state/pi-nix-sync")
        if self.temp is None:
            object.__setattr__(
                self, "temp", Path(os.environ.get("TMPDIR", tempfile.gettempdir()))
            )
        if self.npm_cache is None:
            configured = os.environ.get("npm_config_cache") or os.environ.get(
                "NPM_CONFIG_CACHE"
            )
            object.__setattr__(
                self,
                "npm_cache",
                Path(configured).expanduser() if configured else self.home / ".npm",
            )

    @property
    def pi_root(self) -> Path:
        return self.home / ".pi"

    @property
    def runtime(self) -> Path:
        return self.pi_root / "agent"

    @property
    def project_pi(self) -> Path:
        return self.cwd / ".pi"

    @property
    def agent_skills(self) -> Path:
        return self.home / ".agents/skills"


def default_npm_cache(home: Path) -> Path:
    configured = os.environ.get("npm_config_cache") or os.environ.get(
        "NPM_CONFIG_CACHE"
    )
    if configured:
        return Path(configured).expanduser()
    try:
        result = subprocess.run(
            ["npm", "config", "get", "cache"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        )
        value = result.stdout.strip()
        if value:
            return Path(value).expanduser()
    except (OSError, subprocess.SubprocessError):
        pass
    return home / ".npm"


def _lstat(path: Path) -> os.stat_result:
    try:
        return path.lstat()
    except FileNotFoundError:
        raise PiConfigError(f"path disappeared while being inspected: {path}") from None


def _is_missing(path: Path) -> bool:
    try:
        path.lstat()
        return False
    except FileNotFoundError:
        return True


def _canonical_json(value: object) -> bytes:
    return (
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    ).encode("utf-8")


def _read_json_object(data: bytes, path: Path) -> dict[str, object]:
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PiConfigError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(value, dict):
        raise PiConfigError(f"{path} must contain a JSON object")
    return value


def _normalized_secret_key(key: str) -> str:
    return re.sub(r"[^a-z0-9]", "", key.lower())


def _is_sensitive_key(key: str) -> bool:
    normalized = _normalized_secret_key(key)
    exact = {
        "apikey",
        "apitoken",
        "token",
        "accesstoken",
        "refreshtoken",
        "authtoken",
        "auth",
        "authentication",
        "authorization",
        "proxyauthorization",
        "xapikey",
        "cookie",
        "setcookie",
    }
    sensitive_suffixes = (
        "apikey",
        "token",
        "authentication",
        "authorization",
    )
    return normalized in exact or normalized.endswith(sensitive_suffixes)


def _allowed_secret_reference(value: str) -> bool:
    return bool(ENV_REFERENCE.fullmatch(value)) or (
        value.startswith("!") and len(value) > 1
    )


def _reject_literal_secret_values(value: object, path: str) -> None:
    if isinstance(value, str):
        if not _allowed_secret_reference(value):
            raise PiConfigError(
                f"models.json contains a literal secret at {path}; use $ENV_VAR or !command"
            )
        return
    if isinstance(value, Mapping):
        for key, child in value.items():
            _reject_literal_secret_values(child, f"{path}.{key}")
        return
    if isinstance(value, Sequence) and not isinstance(value, (bytes, bytearray, str)):
        for index, child in enumerate(value):
            _reject_literal_secret_values(child, f"{path}[{index}]")
        return
    if value is not None:
        raise PiConfigError(
            f"models.json contains a literal secret at {path}; use $ENV_VAR or !command"
        )


def validate_models(value: Mapping[str, object]) -> None:
    def visit(node: object, path: str) -> None:
        if isinstance(node, Mapping):
            for key, child in node.items():
                child_path = f"{path}.{key}" if path else str(key)
                if _is_sensitive_key(str(key)):
                    _reject_literal_secret_values(child, child_path)
                else:
                    visit(child, child_path)
        elif isinstance(node, Sequence) and not isinstance(
            node, (bytes, bytearray, str)
        ):
            for index, child in enumerate(node):
                visit(child, f"{path}[{index}]")

    visit(value, "")


def _read_directory(path: Path, *, ignore_gitkeep: bool) -> Entry:
    root_stat = _lstat(path)
    if stat.S_ISLNK(root_stat.st_mode):
        raise PiConfigError(f"managed path must not be a symlink: {path}")
    if not stat.S_ISDIR(root_stat.st_mode):
        raise PiConfigError(f"managed directory is not a directory: {path}")
    directories: list[tuple[str, int]] = []
    files: list[tuple[str, FileData]] = []

    def visit(directory: Path, relative: Path) -> None:
        try:
            children = sorted(os.scandir(directory), key=lambda child: child.name)
        except OSError as error:
            raise PiConfigError(
                f"cannot inspect managed directory {directory}: {error}"
            ) from error
        for child in children:
            if ignore_gitkeep and child.name == ".gitkeep":
                continue
            child_path = directory / child.name
            child_relative = relative / child.name
            child_stat = child.stat(follow_symlinks=False)
            relative_text = child_relative.as_posix()
            if stat.S_ISLNK(child_stat.st_mode):
                raise PiConfigError(
                    f"managed trees must not contain symlinks: {child_path}"
                )
            if stat.S_ISDIR(child_stat.st_mode):
                directories.append((relative_text, stat.S_IMODE(child_stat.st_mode)))
                visit(child_path, child_relative)
            elif stat.S_ISREG(child_stat.st_mode):
                try:
                    data = child_path.read_bytes()
                except OSError as error:
                    raise PiConfigError(
                        f"cannot read managed file {child_path}: {error}"
                    ) from error
                files.append(
                    (relative_text, FileData(data, stat.S_IMODE(child_stat.st_mode)))
                )
            else:
                raise PiConfigError(
                    f"managed trees must contain only regular files and directories: {child_path}"
                )

    visit(path, Path())
    return Entry(
        "directory",
        stat.S_IMODE(root_stat.st_mode),
        directories=tuple(directories),
        files=tuple(files),
    )


def read_entry(
    path: Path, name: str, *, normalized: bool, ignore_gitkeep: bool = True
) -> Entry | None:
    try:
        path_stat = path.lstat()
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(path_stat.st_mode):
        raise PiConfigError(f"managed path must not be a symlink: {path}")
    if name in DIRECTORY_NAMES:
        return _read_directory(path, ignore_gitkeep=ignore_gitkeep)
    if not stat.S_ISREG(path_stat.st_mode):
        raise PiConfigError(f"managed file is not a regular file: {path}")
    try:
        data = path.read_bytes()
    except OSError as error:
        raise PiConfigError(f"cannot read managed file {path}: {error}") from error
    mode = stat.S_IMODE(path_stat.st_mode)
    if name == "settings.json":
        value = _read_json_object(data, path)
        if normalized:
            for key in RUNTIME_SETTING_KEYS:
                value.pop(key, None)
            if not value:
                return None
            data = _canonical_json(value)
    elif name in {
        "keybindings.json",
        "models.json",
        "pi-codex-conversion.json",
    }:
        value = _read_json_object(data, path)
        if name == "models.json":
            validate_models(value)
        data = _canonical_json(value)
    return Entry("file", mode, file=FileData(data, mode))


def read_projection(root: Path, *, normalized: bool = True) -> Projection:
    try:
        root_stat = root.lstat()
    except FileNotFoundError:
        return Projection({})
    if stat.S_ISLNK(root_stat.st_mode):
        raise PiConfigError(f"configuration root must not be a symlink: {root}")
    if not stat.S_ISDIR(root_stat.st_mode):
        raise PiConfigError(f"configuration root must be a directory: {root}")
    entries: dict[str, Entry] = {}
    for name in MANAGED_NAMES:
        entry = read_entry(root / name, name, normalized=normalized)
        if entry is not None:
            entries[name] = entry
    return Projection(entries)


def entries_equal(left: Entry | None, right: Entry | None) -> bool:
    if left is None or right is None:
        return left is right
    return left.digest() == right.digest()


def projections_equal(left: Projection, right: Projection) -> bool:
    return all(
        entries_equal(left.entry(name), right.entry(name)) for name in MANAGED_NAMES
    )


def optional_projections_equal(
    left: Projection | None, right: Projection | None
) -> bool:
    if left is None or right is None:
        return left is right
    return projections_equal(left, right)


def operation_views_equal(left: OperationView, right: OperationView) -> bool:
    return (
        left.plan.operation == right.plan.operation
        and left.plan.states == right.plan.states
        and left.plan.replacements == right.plan.replacements
        and left.plan.unresolved == right.plan.unresolved
        and projections_equal(left.plan.source, right.plan.source)
        and projections_equal(left.target, right.target)
        and optional_projections_equal(left.baseline, right.baseline)
        and optional_projections_equal(left.other_baseline, right.other_baseline)
        and projections_equal(left.desired_target, right.desired_target)
    )


def materialize_entry(
    entry: Entry, destination: Path, *, owner_writable: bool = True
) -> None:
    if entry.kind == "file":
        assert entry.file is not None
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(entry.file.data)
        mode = entry.file.mode
        if owner_writable:
            mode |= stat.S_IRUSR | stat.S_IWUSR
        destination.chmod(mode)
        return
    destination.mkdir(parents=True, exist_ok=False)
    root_mode = entry.mode
    if owner_writable:
        root_mode |= stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR
    destination.chmod(root_mode)
    for relative, mode in entry.directories:
        directory = destination / relative
        directory.mkdir(parents=True, exist_ok=False)
        if owner_writable:
            mode |= stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR
        directory.chmod(mode)
    for relative, file_data in entry.files:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(file_data.data)
        mode = file_data.mode
        if owner_writable:
            mode |= stat.S_IRUSR | stat.S_IWUSR
        target.chmod(mode)


def materialize_projection(
    projection: Projection, destination: Path, *, marker: bool = False
) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    for name in MANAGED_NAMES:
        entry = projection.entry(name)
        if entry is not None:
            materialize_entry(entry, destination / name)
    if marker:
        (destination / BASE_MARKER).write_text("pi-nix-sync-v1\n", encoding="utf-8")


def remove_path(path: Path) -> None:
    try:
        path_stat = path.lstat()
    except FileNotFoundError:
        return
    if stat.S_ISDIR(path_stat.st_mode) and not stat.S_ISLNK(path_stat.st_mode):
        shutil.rmtree(path)
    else:
        path.unlink()


def _nearest_existing_directory(path: Path) -> Path:
    candidate = path
    while True:
        try:
            candidate_stat = candidate.lstat()
        except FileNotFoundError:
            parent = candidate.parent
            if parent == candidate:
                raise PiConfigError(f"no existing ancestor for {path}")
            candidate = parent
            continue
        if stat.S_ISLNK(candidate_stat.st_mode) or not stat.S_ISDIR(
            candidate_stat.st_mode
        ):
            raise PiConfigError(
                f"staging ancestor is not a real directory: {candidate}"
            )
        return candidate


def _mkdir_with_tracking(path: Path) -> list[Path]:
    missing: list[Path] = []
    candidate = path
    while _is_missing(candidate):
        missing.append(candidate)
        if candidate.parent == candidate:
            break
        candidate = candidate.parent
    for directory in reversed(missing):
        directory.mkdir()
    return missing


def _prune_created(directories: Iterable[Path]) -> None:
    for directory in directories:
        try:
            directory.rmdir()
        except OSError:
            pass


def _fsync_path(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _fsync_tree(path: Path) -> None:
    try:
        path_stat = path.lstat()
    except FileNotFoundError:
        return
    if stat.S_ISLNK(path_stat.st_mode):
        raise PiConfigError(f"cannot make a symlink durable: {path}")
    if stat.S_ISREG(path_stat.st_mode):
        _fsync_path(path)
        return
    if not stat.S_ISDIR(path_stat.st_mode):
        raise PiConfigError(f"cannot make a special file durable: {path}")
    directories: list[Path] = []
    for current, directory_names, file_names in os.walk(path, followlinks=False):
        current_path = Path(current)
        directories.append(current_path)
        for name in file_names:
            child = current_path / name
            child_stat = child.lstat()
            if stat.S_ISLNK(child_stat.st_mode) or not stat.S_ISREG(child_stat.st_mode):
                raise PiConfigError(
                    f"cannot make non-regular staged path durable: {child}"
                )
            _fsync_path(child)
        for name in directory_names:
            child = current_path / name
            if child.is_symlink():
                raise PiConfigError(f"cannot make a symlink durable: {child}")
    for directory in reversed(directories):
        _fsync_path(directory)


def _raw_entry(path: Path) -> Entry | None:
    try:
        path_stat = path.lstat()
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(path_stat.st_mode):
        raise PiConfigError(f"transaction target must not be a symlink: {path}")
    if stat.S_ISREG(path_stat.st_mode):
        data = path.read_bytes()
        mode = stat.S_IMODE(path_stat.st_mode)
        return Entry("file", mode, file=FileData(data, mode))
    if stat.S_ISDIR(path_stat.st_mode):
        return _read_directory(path, ignore_gitkeep=False)
    raise PiConfigError(f"transaction target is a special file: {path}")


def _runtime_settings(runtime: Path) -> dict[str, object]:
    path = runtime / "settings.json"
    try:
        path_stat = path.lstat()
    except FileNotFoundError:
        return {}
    if stat.S_ISLNK(path_stat.st_mode) or not stat.S_ISREG(path_stat.st_mode):
        raise PiConfigError(f"managed settings must be a regular file: {path}")
    value = _read_json_object(path.read_bytes(), path)
    return {key: value[key] for key in RUNTIME_SETTING_KEYS if key in value}


def _settings_entry(value: Mapping[str, object], mode: int = 0o600) -> Entry | None:
    if not value:
        return None
    data = _canonical_json(value)
    return Entry("file", mode, file=FileData(data, mode))


def _desired_apply_projection(source: Projection, runtime: Path) -> Projection:
    entries = dict(source.entries)
    extras = _runtime_settings(runtime)
    portable_entry = source.entry("settings.json")
    portable: dict[str, object] = {}
    mode = 0o600
    if portable_entry is not None:
        assert portable_entry.file is not None
        portable = _read_json_object(portable_entry.file.data, Path("settings.json"))
        mode = portable_entry.file.mode
    try:
        current_stat = (runtime / "settings.json").lstat()
        if stat.S_ISREG(current_stat.st_mode):
            mode = stat.S_IMODE(current_stat.st_mode)
    except FileNotFoundError:
        pass
    portable.update(extras)
    settings = _settings_entry(portable, mode)
    if settings is None:
        entries.pop("settings.json", None)
    else:
        entries["settings.json"] = settings
    return Projection(entries)


def load_baseline(path: Path) -> Projection | None:
    try:
        path_stat = path.lstat()
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(path_stat.st_mode) or not stat.S_ISDIR(path_stat.st_mode):
        raise PiConfigError(f"invalid baseline path: {path}")
    if not (path / BASE_MARKER).is_file():
        raise PiConfigError(f"baseline is incomplete (missing {BASE_MARKER}): {path}")
    return read_projection(path)


def _direction_labels(operation: str) -> tuple[str, str]:
    return (
        ("flake-only", "runtime-only")
        if operation == "apply"
        else ("runtime-only", "flake-only")
    )


def build_plan(
    operation: str,
    source: Projection,
    target: Projection,
    baseline: Projection | None,
    other_baseline: Projection | None,
    *,
    take_source: bool,
) -> SyncPlan:
    source_only, target_only = _direction_labels(operation)
    states: dict[str, str] = {}
    replacements: list[str] = []
    unresolved: list[str] = []
    target_empty = target.is_empty()

    for name in MANAGED_NAMES:
        source_entry = source.entry(name)
        target_entry = target.entry(name)
        if entries_equal(source_entry, target_entry):
            states[name] = "equal"
            continue

        path_baseline = baseline
        if path_baseline is None and other_baseline is not None:
            other_entry = other_baseline.entry(name)
            if entries_equal(source_entry, other_entry) or entries_equal(
                target_entry, other_entry
            ):
                path_baseline = other_baseline

        if path_baseline is None:
            state = source_only if target_empty else "conflict"
        else:
            base_entry = path_baseline.entry(name)
            source_changed = not entries_equal(source_entry, base_entry)
            target_changed = not entries_equal(target_entry, base_entry)
            if source_changed and not target_changed:
                state = source_only
            elif not source_changed and target_changed:
                state = target_only
            elif source_changed and target_changed:
                state = "conflict"
            else:
                # The unequal source/target check above makes this unreachable unless
                # an Entry implementation is inconsistent.
                raise AssertionError(f"inconsistent state for {name}")
        states[name] = state
        if state == source_only or (state == "conflict" and take_source):
            replacements.append(name)
        elif state in {target_only, "conflict"}:
            unresolved.append(name)

    return SyncPlan(operation, states, tuple(replacements), tuple(unresolved), source)


def _find_lock_directory(root: Path) -> Path | None:
    try:
        root_stat = root.lstat()
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(root_stat.st_mode) or not stat.S_ISDIR(root_stat.st_mode):
        return None
    pending = [root]
    while pending:
        directory = pending.pop()
        try:
            children = os.scandir(directory)
        except OSError as error:
            raise PiConfigError(
                f"cannot inspect Pi locks under {directory}: {error}"
            ) from error
        with children:
            for child in children:
                try:
                    is_directory = child.is_dir(follow_symlinks=False)
                except OSError as error:
                    raise PiConfigError(
                        f"cannot inspect Pi lock {child.path}: {error}"
                    ) from error
                if not is_directory:
                    continue
                child_path = Path(child.path)
                if child.name.endswith(".lock"):
                    return child_path
                pending.append(child_path)
    return None


class CliLock:
    def __init__(self, path: Path):
        self.path = path
        self.file = None

    def __enter__(self) -> Self:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.file = self.path.open("a+")
        try:
            fcntl.flock(self.file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            self.file.close()
            self.file = None
            if error.errno in {errno.EACCES, errno.EAGAIN}:
                raise PiConfigError(
                    f"another pi-config mutation holds {self.path}"
                ) from None
            raise
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        if self.file is not None:
            fcntl.flock(self.file.fileno(), fcntl.LOCK_UN)
            self.file.close()
            self.file = None


FailureHook = Callable[[str, str | None], None]
PrecommitCheck = Callable[[], None]
DurabilityHook = Callable[[str, Path], None]


def _no_failure(_phase: str, _name: str | None) -> None:
    return


def _no_precommit() -> None:
    return


def _no_durability_hook(_phase: str, _path: Path) -> None:
    return


class Transaction:
    def __init__(
        self,
        state: Path,
        failure_hook: FailureHook = _no_failure,
        durability_hook: DurabilityHook = _no_durability_hook,
    ):
        self.state = state
        self.failure_hook = failure_hook
        self.durability_hook = durability_hook
        self.journal = state / "transaction.json"

    def _durable(self, phase: str, path: Path) -> None:
        _fsync_tree(path)
        self.durability_hook(phase, path)

    def _backup(
        self,
        operation: str,
        target: Path,
        names: Sequence[str],
        base: Path,
    ) -> Path:
        timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        backup = self.state / "backups" / f"{timestamp}-{operation}-{os.getpid()}"
        backup.mkdir(parents=True, exist_ok=False)
        absent: list[str] = []
        target_backup = backup / "target"
        target_backup.mkdir()
        for name in names:
            entry = _raw_entry(target / name)
            if entry is None:
                absent.append(name)
            else:
                materialize_entry(entry, target_backup / name, owner_writable=False)
        base_entry = _raw_entry(base)
        if base_entry is None:
            absent.append("baseline")
        else:
            materialize_entry(base_entry, backup / "baseline", owner_writable=False)
        metadata = {
            "operation": operation,
            "target": str(target),
            "baseline": str(base),
            "absent": absent,
        }
        (backup / "metadata.json").write_text(
            json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        self._durable("backup", backup)
        _fsync_path(backup.parent)
        _fsync_path(self.state)
        return backup

    def run(
        self,
        operation: str,
        target: Path,
        desired_target: Projection,
        names: Sequence[str],
        base: Path,
        desired_base: Projection,
        precommit: PrecommitCheck,
    ) -> Path:
        if self.journal.exists():
            raise PiConfigError(
                f"pending transaction journal requires manual recovery: {self.journal}"
            )

        target_ancestor = _nearest_existing_directory(target)
        staging_root = self.state / "staging"
        staging_root.mkdir(parents=True, exist_ok=True)
        target_stage_parent = (
            staging_root
            if staging_root.stat().st_dev == target_ancestor.stat().st_dev
            else target_ancestor
        )
        target_stage = Path(tempfile.mkdtemp(prefix="target-", dir=target_stage_parent))
        base_stage = Path(tempfile.mkdtemp(prefix="base-", dir=staging_root))
        staged_target = target_stage / "new"
        staged_base = base_stage / "new"
        created_directories: list[Path] = []
        moved_old: dict[str, Path] = {}
        base_old = base_stage / "old"
        base_was_moved = False
        base_new_installed = False
        mutated: list[str] = []
        backup: Path | None = None
        try:
            materialize_projection(desired_target, staged_target)
            materialize_projection(desired_base, staged_base, marker=True)
            # Re-read the complete staged result before touching a target.
            for name in MANAGED_NAMES:
                expected = desired_target.entry(name)
                actual = read_entry(staged_target / name, name, normalized=False)
                if not entries_equal(expected, actual):
                    raise TransactionFailure(
                        f"staged target validation failed for {name}"
                    )
            if not projections_equal(desired_base, read_projection(staged_target)):
                raise TransactionFailure("staged complete target validation failed")
            if not projections_equal(desired_base, read_projection(staged_base)):
                raise TransactionFailure("staged baseline validation failed")
            self._durable("staged-target", staged_target)
            self._durable("staged-base", staged_base)
            _fsync_path(target_stage)
            _fsync_path(base_stage)

            backup = self._backup(operation, target, names, base)
            precommit()
            journal_value = {
                "operation": operation,
                "target": str(target),
                "baseline": str(base),
                "backup": str(backup),
                "paths": list(names),
            }
            journal_tmp = self.state / f".transaction-{os.getpid()}.tmp"
            journal_tmp.write_text(
                json.dumps(journal_value, sort_keys=True) + "\n", encoding="utf-8"
            )
            _fsync_path(journal_tmp)
            os.replace(journal_tmp, self.journal)
            _fsync_path(self.state)
            self.durability_hook("journal-installed", self.journal)
            self.failure_hook("after_journal", None)

            if names:
                created_directories.extend(_mkdir_with_tracking(target))
            for index, name in enumerate(names):
                self.failure_hook("before_replace", name)
                current = target / name
                old_slot = target_stage / f"old-{index}"
                if not _is_missing(current):
                    os.replace(current, old_slot)
                    moved_old[name] = old_slot
                mutated.append(name)
                new_slot = staged_target / name
                if not _is_missing(new_slot):
                    os.replace(new_slot, current)
                self.failure_hook("after_replace", name)

            for name in names:
                current = target / name
                if not _is_missing(current):
                    self._durable("installed-target-entry", current)
            if not _is_missing(target):
                _fsync_path(target)
            if not _is_missing(target.parent):
                _fsync_path(target.parent)
            for directory in created_directories:
                if not _is_missing(directory):
                    _fsync_path(directory)
                if not _is_missing(directory.parent):
                    _fsync_path(directory.parent)
            self.durability_hook("installed-target", target)
            self.failure_hook("after_target", None)

            self.failure_hook("before_base", None)
            if not _is_missing(base):
                os.replace(base, base_old)
                base_was_moved = True
            os.replace(staged_base, base)
            base_new_installed = True
            self._durable("installed-base", base)
            _fsync_path(base.parent)
            self.failure_hook("after_base", None)
            if not projections_equal(read_projection(target), desired_base):
                raise TransactionFailure("installed target validation failed")
            installed_base = load_baseline(base)
            if installed_base is None or not projections_equal(
                installed_base, desired_base
            ):
                raise TransactionFailure("installed baseline validation failed")
            self.journal.unlink()
            _fsync_path(self.state)
            self.durability_hook("journal-removed", self.state)
            return backup
        except Exception as error:
            rollback_errors: list[str] = []
            try:
                if base_new_installed or base_was_moved:
                    remove_path(base)
                    if base_was_moved and not _is_missing(base_old):
                        os.replace(base_old, base)
                    if not _is_missing(base):
                        self._durable("rollback-base", base)
                    _fsync_path(base.parent)
            except (
                OSError
            ) as rollback_error:  # pragma: no cover - catastrophic filesystem failure
                rollback_errors.append(f"baseline: {rollback_error}")
            for name in reversed(mutated):
                try:
                    current = target / name
                    remove_path(current)
                    old_slot = moved_old.get(name)
                    if old_slot is not None and not _is_missing(old_slot):
                        os.replace(old_slot, current)
                    if not _is_missing(current):
                        self._durable("rollback-target-entry", current)
                except OSError as rollback_error:  # pragma: no cover - catastrophic filesystem failure
                    rollback_errors.append(f"{name}: {rollback_error}")
            try:
                if not _is_missing(target):
                    _fsync_path(target)
                if not _is_missing(target.parent):
                    _fsync_path(target.parent)
            except (
                OSError
            ) as rollback_error:  # pragma: no cover - catastrophic filesystem failure
                rollback_errors.append(f"target directory: {rollback_error}")
            _prune_created(created_directories)
            for directory in created_directories:
                if not _is_missing(directory.parent):
                    _fsync_path(directory.parent)
            if not rollback_errors:
                with contextlib.suppress(FileNotFoundError):
                    self.journal.unlink()
                _fsync_path(self.state)
            message = f"transaction failed and was rolled back: {error}"
            if rollback_errors:
                message += "; rollback errors: " + "; ".join(rollback_errors)
            raise TransactionFailure(message) from error
        finally:
            shutil.rmtree(target_stage, ignore_errors=True)
            shutil.rmtree(base_stage, ignore_errors=True)


class SyncEngine:
    def __init__(
        self,
        paths: RuntimePaths,
        *,
        env: Mapping[str, str] | None = None,
        uid: int | None = None,
        access: Callable[[os.PathLike[str] | str, int], bool] = os.access,
        failure_hook: FailureHook = _no_failure,
        precommit_hook: PrecommitCheck = _no_precommit,
        durability_hook: DurabilityHook = _no_durability_hook,
    ):
        self.paths = paths
        self.env = os.environ if env is None else env
        self.uid = os.getuid() if uid is None else uid
        self.access = access
        self.failure_hook = failure_hook
        self.precommit_hook = precommit_hook
        self.durability_hook = durability_hook

    @property
    def state(self) -> Path:
        assert self.paths.state is not None
        return self.paths.state

    def _reject_redirection(self) -> None:
        if "PI_CODING_AGENT_DIR" in self.env:
            raise PiConfigError(
                "PI_CODING_AGENT_DIR is set; pi-config only synchronizes Pi's default ~/.pi/agent directory"
            )

    def _validate_existing_root(self, path: Path, *, writable: bool) -> None:
        try:
            path_stat = path.lstat()
        except FileNotFoundError:
            return
        if stat.S_ISLNK(path_stat.st_mode):
            raise PiConfigError(f"synchronization path must not be a symlink: {path}")
        if not stat.S_ISDIR(path_stat.st_mode):
            raise PiConfigError(f"synchronization path must be a directory: {path}")
        if path_stat.st_uid != self.uid:
            raise PiConfigError(
                f"synchronization path is owned by uid {path_stat.st_uid}, not {self.uid}: {path}"
            )
        if writable and not self.access(path, os.W_OK | os.X_OK):
            raise PiConfigError(f"synchronization path is not writable: {path}")

    def _validate_runtime(self) -> None:
        self._validate_existing_root(self.paths.pi_root, writable=True)
        self._validate_existing_root(self.paths.runtime, writable=True)
        for name in MANAGED_NAMES:
            self._validate_live_managed_path(self.paths.runtime / name)

    def _validate_live_managed_path(self, path: Path) -> None:
        try:
            path_stat = path.lstat()
        except FileNotFoundError:
            return
        if stat.S_ISLNK(path_stat.st_mode):
            kind = "store-linked" if _points_into_store(path) else "symlinked"
            raise PiConfigError(f"managed live Pi path is {kind}: {path}")
        if path_stat.st_uid != self.uid:
            raise PiConfigError(
                f"managed live Pi path is owned by uid {path_stat.st_uid}, not {self.uid}: {path}"
            )
        mode = os.W_OK | (os.X_OK if stat.S_ISDIR(path_stat.st_mode) else 0)
        if not self.access(path, mode):
            raise PiConfigError(f"managed live Pi path is not writable: {path}")
        if stat.S_ISDIR(path_stat.st_mode):
            try:
                children = os.scandir(path)
            except OSError as error:
                raise PiConfigError(
                    f"cannot inspect managed live Pi path {path}: {error}"
                ) from error
            with children:
                for child in children:
                    self._validate_live_managed_path(Path(child.path))

    def _check_pi_locks(self) -> None:
        for root in (self.paths.runtime, self.paths.project_pi):
            lock = _find_lock_directory(root)
            if lock is not None:
                raise PiConfigError(
                    f"Pi appears to be running ({lock}); exit Pi before synchronizing"
                )

    def _check_pending_journal(self) -> None:
        journal = self.state / "transaction.json"
        if journal.exists():
            raise PiConfigError(
                f"pending transaction journal requires manual recovery: {journal}"
            )

    def _snapshot(self) -> Projection:
        if self.paths.snapshot is None:
            raise PiConfigError("no embedded Pi configuration snapshot is available")
        return read_projection(self.paths.snapshot)

    def _plan_apply(self, take_flake: bool) -> OperationView:
        flake = self._snapshot()
        runtime = read_projection(self.paths.runtime)
        base = load_baseline(self.state / "applied-base")
        other = load_baseline(self.state / "capture-base")
        plan = build_plan("apply", flake, runtime, base, other, take_source=take_flake)
        return OperationView(
            plan,
            runtime,
            base,
            other,
            _desired_apply_projection(flake, self.paths.runtime),
        )

    def _plan_capture(self, config: Path, take_runtime: bool) -> OperationView:
        runtime = read_projection(self.paths.runtime)
        flake = read_projection(config)
        base = load_baseline(self.state / "capture-base")
        other = load_baseline(self.state / "applied-base")
        plan = build_plan(
            "capture", runtime, flake, base, other, take_source=take_runtime
        )
        return OperationView(plan, flake, base, other, runtime)

    def status(self) -> SyncStatus:
        self._reject_redirection()
        self._validate_runtime()
        self._check_pi_locks()
        self._check_pending_journal()
        apply = self._plan_apply(False).plan
        assert self.paths.snapshot is not None
        capture = self._plan_capture(self.paths.snapshot, False).plan
        return SyncStatus(apply, capture)

    def diff(self) -> tuple[str, bool]:
        self._reject_redirection()
        self._validate_runtime()
        self._check_pi_locks()
        self._check_pending_journal()
        flake = self._snapshot()
        runtime = read_projection(self.paths.runtime)
        output: list[str] = []
        different = False
        for name in MANAGED_NAMES:
            left = flake.entry(name)
            right = runtime.entry(name)
            if entries_equal(left, right):
                continue
            different = True
            left_lines = _entry_diff_lines(left)
            right_lines = _entry_diff_lines(right)
            output.extend(
                difflib.unified_diff(
                    left_lines,
                    right_lines,
                    fromfile=f"flake/{name}",
                    tofile=f"runtime/{name}",
                    lineterm="",
                )
            )
        return "\n".join(output) + ("\n" if output else ""), different

    def apply(self, *, take_flake: bool = False) -> SyncResult:
        self._reject_redirection()
        self._validate_runtime()
        self._check_pi_locks()
        self._check_pending_journal()
        preliminary = self._plan_apply(take_flake)
        if preliminary.plan.unresolved:
            raise SyncConflict("apply", preliminary.plan.states)
        with CliLock(self.state / "cli.lock"):
            self._validate_runtime()
            self._check_pi_locks()
            self._check_pending_journal()
            locked = self._plan_apply(take_flake)
            if locked.plan.unresolved:
                raise SyncConflict("apply", locked.plan.states)

            def precommit() -> None:
                self.precommit_hook()
                self._validate_runtime()
                self._check_pi_locks()
                self._check_pending_journal()
                if not operation_views_equal(locked, self._plan_apply(take_flake)):
                    raise PiConfigError(
                        "apply inputs changed while the transaction was staged"
                    )

            transaction = Transaction(
                self.state, self.failure_hook, self.durability_hook
            )
            backup = transaction.run(
                "apply",
                self.paths.runtime,
                locked.desired_target,
                locked.plan.replacements,
                self.state / "applied-base",
                locked.plan.source,
                precommit,
            )
            return SyncResult(
                "apply", locked.plan.states, locked.plan.replacements, backup
            )

    def capture(self, config: Path, *, take_runtime: bool = False) -> SyncResult:
        self._reject_redirection()
        self._validate_runtime()
        self._validate_capture_target(config)
        self._check_pi_locks()
        self._check_pending_journal()
        preliminary = self._plan_capture(config, take_runtime)
        if preliminary.plan.unresolved:
            raise SyncConflict("capture", preliminary.plan.states)
        with CliLock(self.state / "cli.lock"):
            self._validate_runtime()
            self._validate_capture_target(config)
            self._check_pi_locks()
            self._check_pending_journal()
            plan = self._plan_capture(config, take_runtime)
            if plan.plan.unresolved:
                raise SyncConflict("capture", plan.plan.states)

            def precommit() -> None:
                self.precommit_hook()
                self._validate_runtime()
                self._validate_capture_target(config)
                self._check_pi_locks()
                self._check_pending_journal()
                if not operation_views_equal(
                    plan, self._plan_capture(config, take_runtime)
                ):
                    raise PiConfigError(
                        "capture inputs changed while the transaction was staged"
                    )

            transaction = Transaction(
                self.state, self.failure_hook, self.durability_hook
            )
            backup = transaction.run(
                "capture",
                config,
                plan.desired_target,
                plan.plan.replacements,
                self.state / "capture-base",
                plan.plan.source,
                precommit,
            )
            return SyncResult(
                "capture", plan.plan.states, plan.plan.replacements, backup
            )

    def _validate_capture_target(self, config: Path) -> None:
        existing = _nearest_existing_directory(config)
        if not self.access(existing, os.W_OK | os.X_OK):
            raise PiConfigError(
                f"portable configuration parent is not writable: {existing}"
            )
        try:
            config_stat = config.lstat()
        except FileNotFoundError:
            return
        if stat.S_ISLNK(config_stat.st_mode) or not stat.S_ISDIR(config_stat.st_mode):
            raise PiConfigError(
                f"portable configuration root must be a real directory: {config}"
            )

    def doctor(self) -> list[str]:
        problems: list[str] = []
        if "PI_CODING_AGENT_DIR" in self.env:
            problems.append(
                "PI_CODING_AGENT_DIR is set; Pi is redirected away from ~/.pi/agent"
            )
        roots = (
            (self.paths.pi_root, True, True),
            (self.paths.runtime, True, True),
            (self.paths.project_pi, True, True),
            (self.paths.agent_skills, True, True),
            (self.paths.temp, False, False),
            (self.paths.npm_cache, False, False),
        )
        seen: set[Path] = set()
        for path, enforce_owner, recursive in roots:
            assert path is not None
            if path in seen:
                continue
            seen.add(path)
            if path == self.paths.temp and _is_missing(path):
                problems.append(f"temporary directory does not exist: {path}")
                continue
            problems.extend(
                self._doctor_path(
                    path, enforce_owner=enforce_owner, recursive=recursive
                )
            )
        journal = self.state / "transaction.json"
        try:
            journal.lstat()
        except FileNotFoundError:
            pass
        else:
            problems.append(
                f"pending transaction journal requires manual recovery: {journal}"
            )
        return problems

    def _doctor_path(
        self, path: Path, *, enforce_owner: bool, recursive: bool
    ) -> list[str]:
        try:
            path_stat = path.lstat()
        except FileNotFoundError:
            return []
        problems: list[str] = []
        if stat.S_ISLNK(path_stat.st_mode):
            if not enforce_owner:
                if not self.access(path, os.W_OK):
                    problems.append(f"unwritable path: {path}")
                return problems
            if _points_into_store(path):
                problems.append(f"store-linked path: {path}")
            else:
                problems.append(f"symlinked path: {path}")
            return problems
        if not stat.S_ISDIR(path_stat.st_mode):
            problems.append(f"expected a directory: {path}")
            return problems
        if enforce_owner and path_stat.st_uid != self.uid:
            problems.append(f"foreign-owned path (uid {path_stat.st_uid}): {path}")
        if not self.access(
            path, os.W_OK | (os.X_OK if stat.S_ISDIR(path_stat.st_mode) else 0)
        ):
            problems.append(f"unwritable path: {path}")
        if recursive and stat.S_ISDIR(path_stat.st_mode):
            for current, directory_names, file_names in os.walk(
                path, followlinks=False
            ):
                current_path = Path(current)
                for name in tuple(directory_names) + tuple(file_names):
                    child = current_path / name
                    child_stat = child.lstat()
                    if stat.S_ISLNK(child_stat.st_mode):
                        if _points_into_store(child):
                            problems.append(f"store-linked path: {child}")
                        continue
                    if enforce_owner and child_stat.st_uid != self.uid:
                        problems.append(
                            f"foreign-owned path (uid {child_stat.st_uid}): {child}"
                        )
                    mode = os.W_OK | (
                        os.X_OK if stat.S_ISDIR(child_stat.st_mode) else 0
                    )
                    if not self.access(child, mode):
                        problems.append(f"unwritable path: {child}")
        return problems

    def activation_preflight(self) -> list[str]:
        problems: list[str] = []
        pi = self.paths.pi_root
        try:
            pi_stat = pi.lstat()
        except FileNotFoundError:
            pi_stat = None
        ownership_problem = False
        if pi_stat is not None:
            if stat.S_ISLNK(pi_stat.st_mode):
                problems.append(f"~/.pi must not be a symlink: {pi}")
            elif not stat.S_ISDIR(pi_stat.st_mode):
                problems.append(f"~/.pi must be a directory: {pi}")
            else:
                for current, directory_names, file_names in os.walk(
                    pi, followlinks=False
                ):
                    for item in (Path(current),) + tuple(
                        Path(current) / name for name in directory_names + file_names
                    ):
                        item_stat = item.lstat()
                        if stat.S_ISLNK(item_stat.st_mode):
                            if _points_into_store(item):
                                problems.append(f"store-linked Pi path: {item}")
                            continue
                        if item_stat.st_uid != self.uid:
                            ownership_problem = True
                            problems.append(
                                f"foreign-owned Pi path (uid {item_stat.st_uid}): {item}"
                            )
                        mode = os.W_OK | (
                            os.X_OK if stat.S_ISDIR(item_stat.st_mode) else 0
                        )
                        if not self.access(item, mode):
                            problems.append(f"unwritable Pi path: {item}")
        if ownership_problem:
            problems.append('sudo chown -R "$(id -un):$(id -gn)" "$HOME/.pi"')

        legacy = (
            self.paths.home / ".omp/agent/APPEND_SYSTEM.md",
            self.paths.home / ".omp/agent/lsp.json",
            self.paths.home / ".omp/agent/themes/gruvbox-night.json",
        )
        for path in legacy:
            if path.is_symlink() and _points_into_home_manager_files(path):
                template = str(path) + ".pi-config.XXXXXX"
                problems.append(f"legacy OMP file is Home Manager store-linked: {path}")
                problems.append(
                    "dereference manually: "
                    f"omp_tmp=$(mktemp {shlex.quote(template)}) && "
                    f'cp -pL -- {shlex.quote(str(path))} "$omp_tmp" && '
                    f'mv -f -- "$omp_tmp" {shlex.quote(str(path))}'
                )
        return problems


def _entry_diff_lines(entry: Entry | None) -> list[str]:
    if entry is None:
        return ["<absent>"]
    if entry.kind == "file":
        assert entry.file is not None
        try:
            return entry.file.data.decode("utf-8").splitlines()
        except UnicodeDecodeError:
            return [
                f"<binary sha256={hashlib.sha256(entry.file.data).hexdigest()} executable={bool(entry.file.mode & 0o111)}>"
            ]
    lines = ["<directory>"]
    lines.extend(
        f"dir {relative}/ executable={bool(mode & 0o111)}"
        for relative, mode in entry.directories
    )
    for relative, file_data in entry.files:
        lines.append(
            f"file {relative} sha256={hashlib.sha256(file_data.data).hexdigest()} executable={bool(file_data.mode & 0o111)}"
        )
    return lines


def _points_into_store(path: Path) -> bool:
    if not path.is_symlink():
        return False
    target = os.readlink(path)
    resolved = (
        (path.parent / target).resolve(strict=False)
        if not os.path.isabs(target)
        else Path(target)
    )
    return str(resolved) == "/nix/store" or str(resolved).startswith("/nix/store/")


def _points_into_home_manager_files(path: Path) -> bool:
    if not _points_into_store(path):
        return False
    target = os.readlink(path)
    resolved = (
        (path.parent / target).resolve(strict=False)
        if not os.path.isabs(target)
        else Path(target)
    )
    try:
        relative = resolved.relative_to("/nix/store")
    except ValueError:
        return False
    return bool(relative.parts and relative.parts[0].endswith("-home-manager-files"))


def discover_flake_root(start: Path) -> Path:
    candidate = start.resolve()
    while True:
        if (candidate / "home/pi/config").is_dir():
            return candidate
        if candidate.parent == candidate:
            raise PiConfigError(
                "could not find home/pi/config above the current directory; pass --flake-root PATH"
            )
        candidate = candidate.parent


def _print_plan(label: str, plan: SyncPlan) -> None:
    print(f"[{label}]")
    for name in MANAGED_NAMES:
        print(f"{name}: {plan.states[name]}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="pi-config", description=__doc__)
    commands = parser.add_subparsers(
        dest="command",
        required=True,
        metavar="{doctor,status,diff,apply,capture}",
    )
    commands.add_parser(
        "doctor", help="check that Pi's ordinary state locations are writable"
    )
    commands.add_parser("status", help="show apply and capture synchronization state")
    commands.add_parser("diff", help="diff the embedded snapshot against ~/.pi/agent")
    apply_parser = commands.add_parser(
        "apply", help="apply the embedded snapshot to ~/.pi/agent"
    )
    apply_parser.add_argument(
        "--take-flake",
        action="store_true",
        help="resolve two-sided conflicts in favor of the flake",
    )
    capture_parser = commands.add_parser(
        "capture", help="capture ~/.pi/agent into home/pi/config"
    )
    capture_parser.add_argument(
        "--take-runtime",
        action="store_true",
        help="resolve two-sided conflicts in favor of runtime",
    )
    capture_parser.add_argument(
        "--flake-root", type=Path, help="flake root containing home/pi/config"
    )
    commands.add_parser("_activation-preflight")
    commands._choices_actions = [
        action
        for action in commands._choices_actions
        if action.dest != "_activation-preflight"
    ]
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    snapshot_value = os.environ.get("PI_CONFIG_SNAPSHOT")
    home = Path.home()
    npm_cache = (
        default_npm_cache(home)
        if arguments.command == "doctor"
        else Path(
            os.environ.get("npm_config_cache")
            or os.environ.get("NPM_CONFIG_CACHE")
            or home / ".npm"
        ).expanduser()
    )
    paths = RuntimePaths(
        home,
        Path.cwd(),
        snapshot=Path(snapshot_value) if snapshot_value else None,
        npm_cache=npm_cache,
    )
    engine = SyncEngine(paths)
    try:
        if arguments.command == "doctor":
            problems = engine.doctor()
            if problems:
                for problem in problems:
                    print(problem, file=sys.stderr)
                return 2
            print("Pi state paths are writable and application-owned")
            return 0
        if arguments.command == "_activation-preflight":
            problems = engine.activation_preflight()
            if problems:
                for problem in problems:
                    print(problem, file=sys.stderr)
                return 2
            return 0
        if arguments.command == "status":
            status = engine.status()
            _print_plan("apply: flake -> runtime", status.apply)
            _print_plan("capture: runtime -> flake", status.capture)
            changed = any(
                plan.unresolved or plan.replacements
                for plan in (status.apply, status.capture)
            )
            return 1 if changed else 0
        if arguments.command == "diff":
            output, different = engine.diff()
            if output:
                sys.stdout.write(output)
            return 1 if different else 0
        if arguments.command == "apply":
            result = engine.apply(take_flake=arguments.take_flake)
        elif arguments.command == "capture":
            root = (
                arguments.flake_root.resolve()
                if arguments.flake_root
                else discover_flake_root(Path.cwd())
            )
            config = root / "home/pi/config"
            result = engine.capture(config, take_runtime=arguments.take_runtime)
        else:  # pragma: no cover - argparse enforces this
            raise AssertionError(arguments.command)
        for name in result.changed:
            print(f"{result.operation}: {name}")
        print(f"recovery backup: {result.backup}")
        return 0
    except SyncConflict as error:
        print(f"pi-config: {error}", file=sys.stderr)
        return 1
    except PiConfigError as error:
        print(f"pi-config: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
