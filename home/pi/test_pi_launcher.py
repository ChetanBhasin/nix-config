"""Offline launcher regressions against the wrapped Pi's actual CLI and SDK.

PI_TEST_PACKAGE_DIR=/path/to/pi-monorepo python3 -m unittest discover \
    -s home/pi -p test_pi_launcher.py -v
Optional PI_TEST_WRAPPER=/nix/store/.../bin/pi also exercises the built wrapper.
Every child runs with temporary HOME, cwd and agent state; no live extensions.
"""
from __future__ import annotations

# unittest initializes instance fixtures in setUp rather than __init__.
# pyright: reportUninitializedInstanceVariable=false
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import tempfile
import tarfile
import unittest
from collections.abc import Mapping
from pathlib import Path
from typing import cast, override

HELPERS = Path(__file__).resolve().parents[2] / "modules/homeManager"
PI_PACKAGE = os.environ.get("PI_TEST_PACKAGE_DIR")
PI_WRAPPER = os.environ.get("PI_TEST_WRAPPER")
RUNTIME = Path(os.environ.get(
    "PI_TEST_RELIABILITY_DIR", str(Path(__file__).resolve().parent / "config/extensions/runtime-reliability"),
))
FLAG_NAMES = [
    "no-tests", "no-opengrep", "no-read-guard", "no-autoformat",
    "no-autofix", "no-lens-context", "lens-compact-tool-line",
]
VALUE_OPTIONS = [
    "--mode", "--provider", "--model", "--api-key", "--system-prompt",
    "--append-system-prompt", "--name", "-n", "--session", "--session-id",
    "--fork", "--session-dir", "--models", "--tools", "-t", "--exclude-tools",
    "-xt", "--thinking", "--export", "--skill", "--prompt-template", "--theme",
]
MANAGEMENT_COMMANDS = ["install", "remove", "uninstall", "update", "list", "config", "auth"]


@unittest.skipUnless(PI_PACKAGE, "set PI_TEST_PACKAGE_DIR to the wrapped Pi package root")
class PiLauncherTests(unittest.TestCase):
    @override
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="pi-launcher-")
        self.addCleanup(temporary.cleanup)
        self.root: Path = Path(temporary.name)
        self.home: Path = self.root / "temporary home % space"
        self.home.mkdir()
        self.agent: Path = self.home / ".pi/agent"
        self.lens: Path = self.agent / "npm/node_modules/pi-lens/dist/index.js"
        self.policy_helper: Path = HELPERS / "pi-launcher-lens.mjs"
        self.cli_entry: str = "/dist/cli.js"
        self.bash: str = shutil.which("bash") or "bash"
        self.node: str = str(Path(shutil.which("node") or "node").resolve())
        self.env: dict[str, str] = {
            "PATH": os.environ.get("PATH", ""), "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "PI_OFFLINE": "1", "PI_TELEMETRY": "0", "PI_SKIP_VERSION_CHECK": "1",
        }
        self.fake_pi: Path = self.root / "fake pi"
        _ = self.fake_pi.write_text(
            f"#!{self.bash}\n"
            + 'if (( $# )); then printf "%s\\0" "$@"; fi\n'
            + 'exit "${FAKE_PI_EXIT:-0}"\n'
        )
        self.fake_pi.chmod(0o755)

    def settings(self, value: Mapping[str, object], project: bool = False) -> None:
        path = (self.root / ".pi" if project else self.agent) / "settings.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        _ = path.write_text(json.dumps(value))

    def install_lens(self, entry: Path | None = None, enabled: bool = False) -> Path:
        entry = entry or self.lens
        entry.parent.mkdir(parents=True, exist_ok=True)
        _ = entry.write_text(
            "export default function(pi) {\n"
            + f"  const flags = {json.dumps(FLAG_NAMES)};\n"
            + '  for (const name of flags) pi.registerFlag(name, {type: "boolean", default: false});\n'
            + '  pi.on("session_start", () => {\n'
            + '    console.log(JSON.stringify({test_policy: flags.every(name => pi.getFlag(name) === true)}));\n'
            + '  });\n}\n'
        )
        _ = (entry.parent.parent / "package.json").write_text(
            '{"name":"pi-lens","version":"4.1.2","type":"module",'
            + '"pi":{"extensions":["./dist/index.js"]}}\n'
        )
        if enabled:
            self.settings({"packages": [str(entry.parent.parent)]})
        return entry

    def launch(self, args: list[str], binary: Path | None = None,
               input_text: str = "", built: bool = False) -> subprocess.CompletedProcess[str]:
        command = ([str(PI_WRAPPER)] if built else [
            self.bash, str(HELPERS / "pi-launcher.sh"), str(binary or self.fake_pi),
            self.node, str(PI_PACKAGE), str(self.policy_helper),
        ])
        return subprocess.run(
            [*command, *args], cwd=self.root, env=self.env, input=input_text,
            text=True, capture_output=True, timeout=30, check=False,
        )

    def assert_argv(self, args: list[str]) -> list[str]:
        result = self.launch(args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "".join(arg + "\0" for arg in args))
        self.assertEqual(result.stderr, "")
        return result.stdout.split("\0")[:-1]

    def real_pi(self) -> Path:
        binary = self.root / "real pi"
        _ = binary.write_text(
            f"#!{self.bash}\nexec {shlex.quote(self.node)} "
            + shlex.quote(str(PI_PACKAGE) + self.cli_entry) + ' "$@"\n'
        )
        binary.chmod(0o755)
        return binary

    def assert_rpc_startup(self, args: list[str], lens: bool,
                           built: bool = False) -> subprocess.CompletedProcess[str]:
        result = self.launch(
            ["--mode", "rpc", "--no-session", "--no-skills", "--no-prompt-templates",
             "--no-themes", "--no-context-files", "--offline", *args], self.real_pi(),
            '{"id":"state","type":"get_state"}\n', built=built,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Unknown option", result.stderr)
        self.assertNotIn("Failed to load extension", result.stderr)
        self.assertNotIn("conflicts with", result.stderr)
        self.assertIn('"success":true', result.stdout)
        self.assertEqual('"test_policy":true' in result.stderr, lens, result.stderr)
        self.assertNotIn('"test_policy":false', result.stderr)
        for line in result.stdout.splitlines():
            _ = cast(object, json.loads(line))
        return result

    def test_argv_does_not_depend_on_installation_or_discovery(self) -> None:
        settings_cases: list[dict[str, object]] = [
            {}, {"packages": []}, {"packages": ["npm:pi-lens@4.1.2"]},
        ]
        for installed in (False, True):
            if installed:
                _ = self.install_lens()
            for settings in settings_cases:
                self.settings(settings)
                for args in ([], ["--mode", "rpc"], ["hello", "-p"]):
                    with self.subTest(installed=installed, settings=settings, args=args):
                        _ = self.assert_argv(args)

    def test_no_extensions_and_explicit_ordering_preserve_argv(self) -> None:
        _ = self.install_lens(enabled=True)
        for disable in ("--no-extensions", "-ne"):
            for extension in ("--extension", "-e"):
                for args in ([disable], [disable, extension, "other.ts"],
                             [extension, "other.ts", disable],
                             [disable, extension, str(self.lens)],
                             [extension, str(self.lens), disable],
                             [disable, "-e", "other.ts", extension, str(self.lens), "-ne"]):
                    with self.subTest(args=args):
                        _ = self.assert_argv(args)

    def test_source_names_urls_and_invalid_sources_are_not_reinterpreted(self) -> None:
        for source in ("npm:pi-lens", "npm:pi-lens@4.1.2", "npm:pi-lens@latest",
                       "npm:pi-lens-extra", "npm:@other/pi-lens", "pi-lens-notes.ts",
                       "file://remote/pi-lens/dist/index.js", "file:///bad%2Fpath", ""):
            with self.subTest(source=source):
                _ = self.assert_argv(["leading prompt", "-p", "-ne", "-e", source])

    def test_delimiter_and_core_option_values_preserve_argv(self) -> None:
        cases = [["--", "-ne"], ["--", "--no-extensions", "-e", "lens.js"],
                 ["-ne", "--", "-e", "lens.js"], ["-e", "--", "-ne"]]
        for option in VALUE_OPTIONS:
            cases.extend([[option, "-ne"], [option, "--", "-ne"],
                          ["-ne", option, "-e", "lens.js"]])
        for args in cases:
            with self.subTest(args=args):
                _ = self.assert_argv(args)

    def test_optional_equals_malformed_and_repeated_flags_preserve_argv(self) -> None:
        options = ["--help", "-h", "--version", "--continue", "--resume", "--print",
                   "-p", "--list-models", "--use-theme", "--tui-mode", "--no-tools",
                   "--offline", "--custom-flag", "--extension=lens.js",
                   "--no-extensions=true", "--system-prompt=-ne", "-e", "--extension"]
        for option in options:
            for args in ([option, "-ne"], ["-ne", option, "-e", "lens.js"]):
                with self.subTest(args=args):
                    _ = self.assert_argv(args)

    def test_argument_bytes_exit_status_and_agent_override(self) -> None:
        self.env["PI_CODING_AGENT_DIR"] = str(self.root / "other agent")
        args = ["-ne", "--", "", "line one\nline two", "a b", "'quoted'", "*", "$(false)"]
        _ = self.assert_argv(args)
        self.env["FAKE_PI_EXIT"] = "23"
        self.assertEqual(self.launch(args).returncode, 23)

    def test_explicit_paths_urls_symlinks_and_hardlinks_in_real_pi(self) -> None:
        _ = self.install_lens()
        alias = self.root / "lens-alias.js"
        alias.symlink_to(self.lens)
        hardlink = self.root / "lens-hardlink.js"
        hardlink.hardlink_to(self.lens)
        directory_alias = self.root / "lens-directory"
        directory_alias.symlink_to(self.lens.parent.parent, target_is_directory=True)
        for source in (str(alias), alias.as_uri(), str(hardlink), str(directory_alias),
                       str(self.lens.relative_to(self.root)), self.lens.as_uri(),
                       self.lens.parent.parent.as_uri(), str(self.lens.parent.parent) + "/",
                       "~/.pi/agent/npm/node_modules/pi-lens/dist/index.js"):
            with self.subTest(source=source):
                _ = self.assert_rpc_startup(["-ne", "-e", source], True)
        separate = self.install_lens(self.root / "separate % install/pi-lens/dist/index.js")
        _ = self.assert_rpc_startup(["-ne", "-e", separate.as_uri()], True)

    def test_settings_filters_in_real_pi(self) -> None:
        _ = self.install_lens()
        cases: tuple[tuple[object, bool], ...] = (
            ("npm:pi-lens@4.1.2", True),
            ({"source": "npm:pi-lens@4.1.2", "extensions": []}, False),
            ({"source": "npm:pi-lens@4.1.2", "extensions": ["!**/*"]}, False),
            ({"source": "npm:pi-lens@4.1.2", "extensions": ["-dist/index.js"]}, False),
            ({"source": "npm:pi-lens@4.1.2", "extensions": ["+dist/index.js"]}, True),
            ({"source": "npm:pi-lens@4.1.2", "autoload": False}, False),
        )
        for package, lens in cases:
            with self.subTest(package=package):
                self.settings({"packages": [package]})
                _ = self.assert_rpc_startup([], lens)
                _ = self.assert_rpc_startup(["-ne", "-e", self.lens.as_uri()], True)

    def test_local_resource_filters_in_real_pi(self) -> None:
        _ = self.install_lens()
        alias = self.agent / "extensions/lens.js"
        alias.parent.mkdir()
        alias.symlink_to(self.lens)
        for entries, lens in (([], True), (["-extensions/lens.js"], False),
                              (["!extensions/**"], False)):
            self.settings({"extensions": entries})
            _ = self.assert_rpc_startup([], lens)

    def test_explicit_project_trust_and_project_overrides_in_real_pi(self) -> None:
        _ = self.install_lens()
        self.settings({"packages": [str(self.lens.parent.parent)]}, project=True)
        _ = self.assert_rpc_startup(["--no-approve"], False)
        _ = self.assert_rpc_startup(["--approve"], True)
        _ = self.assert_rpc_startup([], False)
        self.settings({"defaultProjectTrust": "always"})
        _ = self.assert_rpc_startup([], True)
        self.settings({"packages": ["npm:pi-lens@4.1.2"]})
        self.settings({"packages": [{"source": "npm:pi-lens", "autoload": False,
                                     "extensions": ["-dist/index.js"]}]}, project=True)
        _ = self.assert_rpc_startup(["--approve"], False)
        _ = self.assert_rpc_startup(["--no-approve"], True)

    def test_policy_uses_final_extension_set_after_project_trust(self) -> None:
        _ = self.install_lens()
        self.settings({"packages": [str(self.lens.parent.parent)]}, project=True)
        approver = self.agent / "extensions/trust.js"
        approver.parent.mkdir(parents=True)
        _ = approver.write_text(
            'export default pi => { pi.on("project_trust", () => ({trusted: "yes"})); };\n'
        )
        for default in ("ask", "never"):
            self.settings({"defaultProjectTrust": default})
            for built in ([False, True] if PI_WRAPPER else [False]):
                with self.subTest(default=default, built=built):
                    _ = self.assert_rpc_startup([], True, built)
                    _ = self.assert_rpc_startup(["--no-approve"], False, built)
        _ = approver.write_text(
            'export default pi => { pi.on("project_trust", () => ({trusted: "no"})); };\n'
        )
        self.settings({"defaultProjectTrust": "always"})
        for built in ([False, True] if PI_WRAPPER else [False]):
            _ = self.assert_rpc_startup([], False, built)

    def install_bootstrap(self, manifest: Mapping[str, object] | None = None) -> Path:
        directory = self.agent / "extensions/runtime-reliability"
        directory.mkdir(parents=True, exist_ok=True)
        for name in ("patcher.mjs", "bootstrap.mjs"):
            self.assertTrue((RUNTIME / name).is_file(), "Capture runtime repairs or set PI_TEST_RELIABILITY_DIR")
            _ = shutil.copyfile(RUNTIME / name, directory / name)
        _ = (directory / "patches.json").write_text(json.dumps(manifest or {"packages": []}))
        return directory

    def cold_package(self, broken: bool = False) -> Path:
        name = "pi-cold-launcher-fixture"
        package = self.root / "archive/package"
        package.mkdir(parents=True)
        marker = self.root / "cold-imported"
        before = (
            'import fs from "node:fs";\nconst repaired = false;\n'
            + f'fs.writeFileSync({json.dumps(str(marker))}, repaired ? "repaired" : "UNREPAIRED");\n'
            + 'if (!repaired) throw new Error("Imported before repair");\n'
            + 'export default function () {}\n'
        )
        after = before.replace("const repaired = false;", "const repaired = true;")
        _ = (package / "extension.js").write_text(before + ("// unknown source\n" if broken else ""))
        _ = (package / "package.json").write_text(json.dumps({
            "name": name, "version": "1.0.0", "type": "module", "pi": {"extensions": ["./extension.js"]},
        }))
        archive = self.root / "local package.tgz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(package, arcname="package")
        _ = self.install_bootstrap({"packages": [{"name": name, "version": "1.0.0", "patches": [{
            "file": "extension.js", "beforeHash": hashlib.sha256(before.encode()).hexdigest(),
            "afterHash": hashlib.sha256(after.encode()).hexdigest(),
            "edits": [{"before": "const repaired = false;", "after": "const repaired = true;"}],
        }]}]})
        _ = self.env.pop("PI_OFFLINE", None)
        self.env["npm_config_prefix"] = str(self.root / "npm-global")
        self.settings({
            "packages": [f"npm:{name}@file:{archive}"],
            "npmCommand": [shutil.which("npm") or "npm", "--offline", "--ignore-scripts", "--no-audit",
                           "--no-fund", "--silent", "--cache", str(self.root / "npm-cache")],
        })
        return marker

    def test_cold_runtime_profile_can_report_version_without_packages(self) -> None:
        patches: list[dict[str, object]] = []
        _ = self.install_bootstrap({"packages": [{"name": "missing-fixture", "version": "1.0.0", "patches": patches}]})
        for built in ([False, True] if PI_WRAPPER else [False]):
            result = self.launch(["--version"], self.real_pi(), built=built)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "0.84.4")
            self.assertIn('"missing-fixture@1.0.0"', result.stderr)
            self.assertFalse((self.agent / "npm").exists())

    def test_cold_runtime_installs_then_repairs_before_real_rpc_import(self) -> None:
        marker = self.cold_package()
        for built in ([False, True] if PI_WRAPPER else [False]):
            shutil.rmtree(self.agent / "npm", ignore_errors=True)
            marker.unlink(missing_ok=True)
            result = self.launch(["--mode", "rpc", "--no-session", "--no-context-files"], self.real_pi(),
                                 '{"id":"state","type":"get_state"}\n', built=built)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("Failed to load extension", result.stderr)
            self.assertEqual(marker.read_text(), "repaired")
            self.assertIn('"success":true', result.stdout)
            for line in result.stdout.splitlines():
                _ = cast(object, json.loads(line))

    def test_newly_installed_unknown_source_stops_before_rpc_import(self) -> None:
        marker = self.cold_package(broken=True)
        for built in ([False, True] if PI_WRAPPER else [False]):
            shutil.rmtree(self.agent / "npm", ignore_errors=True)
            marker.unlink(missing_ok=True)
            result = self.launch(["--mode", "rpc", "--no-session", "--no-context-files"], self.real_pi(),
                                 '{"id":"state","type":"get_state"}\n', built=built)
            self.assertNotEqual(result.returncode, 0, result.stderr)
            self.assertIn("Unrecognized source", result.stderr)
            self.assertFalse(marker.exists(), "Unknown extension code must not execute")
            self.assertNotIn('"success":true', result.stdout)

    def test_deferred_preflight_cannot_lose_its_selected_import_guard(self) -> None:
        for built in ([False, True] if PI_WRAPPER else [False]):
            directory = self.install_bootstrap()
            _ = (directory / "patcher.mjs").write_text(
                'import fs from "node:fs"; fs.unlinkSync(new URL("./bootstrap.mjs", import.meta.url));\n'
            )
            result = self.launch(["--version"], self.real_pi(), built=built)
            self.assertNotEqual(result.returncode, 0, result.stderr)
            self.assertIn("bootstrap.mjs", result.stderr)
            self.assertNotIn("0.84.4", result.stdout)

    def install_patcher(self, agent: Path | None = None) -> Path:
        agent = agent or self.agent
        patcher = agent / "extensions/runtime-reliability/patcher.mjs"
        patcher.parent.mkdir(parents=True, exist_ok=True)
        marker = self.root / "preflight.json"
        _ = patcher.write_text(
            'import {writeFileSync} from "node:fs";\n'
            + f'writeFileSync({json.dumps(str(marker))}, JSON.stringify(process.argv));\n'
            + f'writeFileSync({json.dumps(str(marker) + ".env")}, JSON.stringify(process.env.PI_CODING_AGENT_DIR ?? null));\n'
            + 'console.log("fixture repair report");\n'
            + 'process.exitCode = Number(process.env.PATCHER_EXIT ?? 0);\n'
        )
        return marker

    def test_preflight_normalizes_agent_override_like_pi(self) -> None:
        marker = self.install_patcher()
        overrides = ("~/.pi/agent", self.agent.as_uri(), str(self.agent.relative_to(self.root)))
        for agent_override in overrides:
            for exit_code in (0, 19):
                with self.subTest(agent_override=agent_override, exit_code=exit_code):
                    marker.unlink(missing_ok=True)
                    self.env["PI_CODING_AGENT_DIR"] = agent_override
                    self.env["PATCHER_EXIT"] = str(exit_code)
                    result = self.launch(["hello", "-ne"])
                    self.assertEqual(result.returncode, exit_code, result.stderr)
                    self.assertEqual(result.stdout, "" if exit_code else "hello\0-ne\0")
                    self.assertEqual(result.stderr, "fixture repair report\n")
                    argv = cast(list[str], json.loads(marker.read_text()))
                    self.assertEqual(argv[2:], ["--apply", str(self.agent)])
                    self.assertEqual(json.loads(marker.with_suffix(".json.env").read_text()), str(self.agent))
            self.env["PATCHER_EXIT"] = "0"
            for built in ([False, True] if PI_WRAPPER else [False]):
                marker.unlink()
                _ = self.assert_rpc_startup(["-ne"], False, built)
                argv = cast(list[str], json.loads(marker.read_text()))
                self.assertEqual(argv[2:], ["--apply", str(self.agent)])
                self.assertEqual(json.loads(marker.with_suffix(".json.env").read_text()), str(self.agent))

    def test_preflight_uses_selected_node_and_agent_and_stderr(self) -> None:
        fake_node = self.root / "bin/node"
        fake_node.parent.mkdir()
        _ = fake_node.write_text(f"#!{self.bash}\nexit 99\n")
        fake_node.chmod(0o755)
        self.env["PATH"] = str(fake_node.parent) + os.pathsep + self.env["PATH"]
        for use_override in (False, True):
            agent = self.root / "override agent" if use_override else self.agent
            if use_override:
                self.env["PI_CODING_AGENT_DIR"] = str(agent)
            marker = self.install_patcher(agent)
            result = self.launch(["hello", "-ne"])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "hello\0-ne\0")
            self.assertEqual(result.stderr, "fixture repair report\n")
            argv = cast(list[str], json.loads(marker.read_text()))
            self.assertEqual(Path(argv[0]).resolve(), Path(self.node))
            self.assertEqual(argv[2:], ["--apply", str(agent)])

    def test_preflight_runs_before_real_extension_loading(self) -> None:
        _ = self.install_lens()
        _ = self.install_patcher()
        patcher = self.agent / "extensions/runtime-reliability/patcher.mjs"
        _ = patcher.write_text(
            'import {writeFileSync} from "node:fs";\n'
            + 'import {join} from "node:path";\n'
            + 'writeFileSync(join(process.argv[3], "settings.json"), '
            + 'JSON.stringify({packages: ["npm:pi-lens@4.1.2"]}));\n'
        )
        _ = self.assert_rpc_startup([], True)

    def test_preflight_does_not_execute_extension_code_or_repair_packages(self) -> None:
        _ = self.install_lens(enabled=True)
        _ = self.lens.write_text('throw new Error("must not execute during preflight");\n')
        self.settings({"packages": ["npm:pi-lens@99.0.0"]})
        del self.env["PI_OFFLINE"]
        package = self.lens.parent.parent / "package.json"
        before = package.read_bytes()
        _ = self.assert_argv([])
        self.assertEqual(package.read_bytes(), before)

    def test_one_way_flags_cannot_be_reenabled_with_false(self) -> None:
        _ = self.install_lens(enabled=True)
        _ = self.assert_rpc_startup(["--" + name + "=false" for name in FLAG_NAMES], True)

    def test_failed_preflight_stops_before_exec(self) -> None:
        marker = self.install_patcher()
        self.env["PATCHER_EXIT"] = "19"
        result = self.launch(["hello", "-ne"])
        self.assertEqual(result.returncode, 19)
        self.assertTrue(marker.exists())
        self.assertEqual(result.stdout, "")
        self.assertIn("fixture repair report", result.stderr)

    def test_management_bypasses_repair_and_preserves_argv(self) -> None:
        _ = self.install_lens(enabled=True)
        marker = self.install_patcher()
        self.env["PATCHER_EXIT"] = "19"
        for command in MANAGEMENT_COMMANDS:
            for tail in ([], ["--help"], ["-e", "npm:pi-lens"], ["--", "-ne"]):
                with self.subTest(command=command, tail=tail):
                    _ = self.assert_argv([command, *tail])
                    self.assertFalse(marker.exists())
        for args in (["--", "update"], ["-p", "install"], ["--name", "auth"]):
            self.assertEqual(self.launch(args).returncode, 19)

    def test_actual_parser_preserves_messages_and_files(self) -> None:
        cases = [["hello", "-p"], ["hello", "-p", "-ne", "-e", self.lens.as_uri()],
                 ["hello", "world", "-e", str(self.lens)], ["", "-p"],
                 ["@input.txt", "hello", "-p"], ["-p", "hello", "--", "-ne", "@two.txt"]]
        forwarded = [self.assert_argv(args) for args in cases]
        script = """
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
const {parseArgs} = await import(pathToFileURL(process.argv[1] + '/dist/cli/args.js'));
console.log(JSON.stringify(JSON.parse(readFileSync(0, 'utf8')).map(args => {
  const parsed = parseArgs(args);
  return {messages: parsed.messages, files: parsed.fileArgs};
})));
"""
        result = subprocess.run(
            [self.node, "--input-type=module", "-e", script, str(PI_PACKAGE)],
            cwd=self.root, env=self.env, input=json.dumps(cases + forwarded), text=True,
            capture_output=True, timeout=30, check=True,
        )
        parsed = cast(list[dict[str, object]], json.loads(result.stdout))
        self.assertEqual(parsed[0]["messages"], ["hello"])
        self.assertEqual(parsed[:len(cases)], parsed[len(cases):])

    def test_real_startup_disabled_settings_and_file_urls(self) -> None:
        _ = self.install_lens()
        settings_cases: list[dict[str, object]] = [
            {}, {"packages": []},
            {"packages": [{"source": "npm:pi-lens@4.1.2", "extensions": []}]},
        ]
        for built in ([False, True] if PI_WRAPPER else [False]):
            for settings in settings_cases:
                self.settings(settings)
                for args, lens in (([], False), (["-ne"], False),
                                   (["-e", self.lens.as_uri()], True),
                                   (["hello", "-ne", "-e", self.lens.as_uri()], True)):
                    with self.subTest(built=built, settings=settings, args=args):
                        _ = self.assert_rpc_startup(args, lens, built)
            self.settings({"packages": ["npm:pi-lens@4.1.2"]})
            _ = self.assert_rpc_startup(["hello"], True, built)
            for command in MANAGEMENT_COMMANDS:
                result = self.launch([command, "--help"], self.real_pi(), built=built)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("Unknown option", result.stderr)

    def test_real_print_startup_preserves_leading_prompt(self) -> None:
        _ = self.install_lens(enabled=True)
        observer = self.root / "prompt-observer.js"
        _ = observer.write_text(
            'export default function(pi) { pi.on("input", event => {\n'
            + '  console.log(JSON.stringify({test_prompt: event.text}));\n'
            + '  return {action: "handled"};\n}); }\n'
        )
        for extra in ([], ["-ne", "-e", self.lens.as_uri()]):
            result = self.launch(
                ["leading prompt", "-p", "--offline", "--no-session", "--no-context-files",
                 "--no-skills", "--no-themes", "--no-prompt-templates", "--no-approve",
                 "-e", str(observer), *extra], self.real_pi(), built=bool(PI_WRAPPER),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('"test_prompt":"leading prompt"', result.stderr)
            self.assertIn('"test_policy":true', result.stderr)
            self.assertNotIn("Unknown option", result.stderr)

    def test_preload_environment_does_not_leak_into_pi_children(self) -> None:
        self.env["NODE_OPTIONS"] = "--stack-trace-limit=27 --no-warnings"
        _ = self.install_bootstrap()
        observer = self.root / "environment-observer.js"
        _ = observer.write_text(
            'import {execFileSync} from "node:child_process";\n'
            + 'export default pi => { pi.on("session_start", () => {\n'
            + '  const code = "JSON.stringify({options:process.env.NODE_OPTIONS,private:process.env.PI_LAUNCHER_POLICY_PACKAGE??null,bootstrap:process.env.PI_LAUNCHER_REPAIR_BOOTSTRAP??null})";\n'
            + '  const child = JSON.parse(execFileSync(process.execPath, ["-p", code], {encoding:"utf8"}));\n'
            + '  console.log(JSON.stringify({test_environment: {options: process.env.NODE_OPTIONS, private: process.env.PI_LAUNCHER_POLICY_PACKAGE??null, bootstrap:process.env.PI_LAUNCHER_REPAIR_BOOTSTRAP??null, child}}));\n'
            + '}); };\n'
        )
        for built in ([False, True] if PI_WRAPPER else [False]):
            result = self.assert_rpc_startup(["-ne", "-e", str(observer)], False, built)
            line = next(line for line in result.stderr.splitlines() if '"test_environment"' in line)
            expected = {"options": self.env["NODE_OPTIONS"], "private": None, "bootstrap": None}
            self.assertEqual(json.loads(line)["test_environment"], {**expected, "child": expected})

    def test_escaped_preload_path(self) -> None:
        self.policy_helper = self.root / 'policy % space/hélp #quote "file.mjs'
        self.policy_helper.parent.mkdir()
        _ = self.policy_helper.write_bytes((HELPERS / "pi-launcher-lens.mjs").read_bytes())
        _ = self.install_lens(enabled=True)
        _ = self.assert_rpc_startup([], True)

    def test_actual_bundled_cli_uses_the_same_policy(self) -> None:
        self.cli_entry = "/dist/bundle/cli.js"
        _ = self.assert_rpc_startup(["-ne"], False)
        _ = self.install_lens(enabled=True)
        _ = self.assert_rpc_startup([], True)
        _ = self.assert_rpc_startup(["-ne", "-e", self.lens.as_uri()], True)

    def test_policy_reapplies_to_real_sdk_resource_reload(self) -> None:
        script = """
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const root = process.argv[1];
const {DefaultResourceLoader} = await import(pathToFileURL(root + '/dist/core/resource-loader.js'));
const {SettingsManager} = await import(pathToFileURL(root + '/dist/core/settings-manager.js'));
const flags = JSON.parse(process.argv[2]);
const loader = new DefaultResourceLoader({
  cwd: process.cwd(), agentDir: process.env.PI_CODING_AGENT_DIR,
  settingsManager: SettingsManager.inMemory({}),
  noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
  extensionFactories: [pi => { for (const name of flags) pi.registerFlag(name, {type:'boolean', default:false}); }],
});
await loader.reload();
const first = loader.getExtensions();
assert.equal(first.errors.length, 0);
assert.ok(flags.every(name => first.runtime.flagValues.get(name) === true));
await loader.reload();
const second = loader.getExtensions();
assert.notEqual(first.runtime, second.runtime);
assert.equal(second.errors.length, 0);
assert.ok(flags.every(name => second.runtime.flagValues.get(name) === true));
console.log('reload-policy-ok');
"""
        env = self.env | {
            "PI_CODING_AGENT_DIR": str(self.agent),
            "PI_LAUNCHER_POLICY_PACKAGE": str(PI_PACKAGE),
            "NODE_OPTIONS": " --import=" + self.policy_helper.as_uri(),
        }
        result = subprocess.run(
            [self.node, "--input-type=module", "-e", script, str(PI_PACKAGE), json.dumps(FLAG_NAMES)],
            cwd=self.root, env=env, text=True, capture_output=True, timeout=30, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("reload-policy-ok", result.stdout)

    def test_incompatible_lens_interface_fails_closed(self) -> None:
        _ = self.install_lens(enabled=True)
        _ = self.lens.write_text(
            'export default pi => { pi.registerFlag("no-lens-context", {type:"boolean"}); };\n'
        )
        result = self.launch(["--mode", "rpc", "--offline", "--no-session"], self.real_pi(),
                             '{"id":"state","type":"get_state"}\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("incompatible Lens flags", result.stderr)
        self.assertNotIn('"success":true', result.stdout)


if __name__ == "__main__":
    _ = unittest.main()
