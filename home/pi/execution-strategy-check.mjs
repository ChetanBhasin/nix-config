// Parent-owned, post-capture qualification. Never captures, applies or activates.
// CLI has no fixture/path/bypass flags. Imported tests exercise the same gates,
// but injected command results are always labelled fixture-only, never real PASS.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repository = path.resolve(here, '../..');
const hostSelector = 'nixosConfigurations.boris';
const homeSelector = `${hostSelector}.config.home-manager.users.chetan`;
export const selectors = Object.freeze({
  host: hostSelector,
  wrapper: `${homeSelector}.programs.pi-coding-agent.package`,
  package: `${homeSelector}.cb.pi.package`,
});
const success = 'PASS journey live-capture: live projection matches captured configuration and the built Nix executable is qualified without activation';

// Import the synchronizer's read-only projection functions, not its CLI or engine.
// Capture excludes retired tombstones; settings normalization and executable-mode
// semantics come from pi_config itself. Never open live auth/catalog/session data.
const projectionScript = String.raw`
import json, stat, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import pi_config as p
live, captured = map(Path, sys.argv[2:4])
for root in (live, captured):
    if not root.is_dir() or root.is_symlink():
        raise RuntimeError('missing or redirected projection root: ' + str(root))
# The projection intentionally drops .gitkeep; validate its raw type/content first.
for placeholder in captured.rglob('.gitkeep'):
    metadata = placeholder.lstat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_size != 0:
        raise RuntimeError('invalid captured .gitkeep: ' + str(placeholder.relative_to(captured)))
left = p.read_projection(live, excluded_names=p.RETIRED_FILE_NAMES)
right = p.read_projection(captured)
if left.is_empty() or right.is_empty():
    raise RuntimeError('empty managed projection')
allowed = set(p.FILE_NAMES + p.DIRECTORY_NAMES) | {'.gitkeep'}
extras = sorted(child.name for child in captured.iterdir() if child.name not in allowed)
if extras:
    raise RuntimeError('private/runtime or unmanaged captured paths: ' + ', '.join(extras))
settings = json.loads((captured / 'settings.json').read_text())
if any(key in settings for key in p.RUNTIME_SETTING_KEYS):
    raise RuntimeError('runtime settings leaked into capture')
# models.json literal secrets are already rejected by read_projection's validator.
# A managed tree is recursive, not an excuse to capture nested runtime products.
forbidden = {'node_modules', '__pycache__', '.cache', 'caches', 'sessions', 'auth.json',
             'models-store.json', '.npm', '.git', 'state', 'logs'}
for name, entry in right.entries.items():
    for relative, _ in (*entry.directories, *entry.files):
        parts = Path(relative).parts
        if forbidden.intersection(parts) or any(part.endswith(('.sqlite', '.sqlite-wal', '.sqlite-shm', '.db', '.pyc')) for part in parts):
            raise RuntimeError('private/runtime artifact in managed capture: ' + name + '/' + relative)
changed = [name for name in p.MANAGED_NAMES if not p.entries_equal(left.entry(name), right.entry(name))]
print(json.dumps({'equal': not changed, 'changed': changed,
                  'live': {name: entry.digest() for name, entry in left.entries.items()},
                  'captured': {name: entry.digest() for name, entry in right.entries.items()},
                  'excludedLiveNames': sorted(child.name for child in live.iterdir() if child.name not in allowed),
                  'runtimeSettingsExcluded': list(p.RUNTIME_SETTING_KEYS),
                  'privateRuntimeExclusionsChecked': True}))
`;

function cleanEnvironment() {
  // No inherited PI_TEST_* can replace the built wrapper/package or repair source.
  const env = { PATH: process.env.PATH, HOME: os.homedir(), LANG: 'C.UTF-8',
    PYTHONDONTWRITEBYTECODE: '1', JITI_FS_CACHE: '0' };
  return env;
}

function executeCommand({ command, args, cwd, env, timeoutMs }) {
  // Foreground GNU timeout kills the entire command process group on expiry,
  // including unittest's Pi/npm children; no unawaited/background writers.
  const result = spawnSync('timeout', ['--signal=TERM', '--kill-after=5s',
    `${Math.ceil(timeoutMs / 1000)}s`, command, ...args], {
    cwd, env, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
  });
  return { status: result.status, signal: result.signal,
    stdout: result.stdout ?? '', stderr: result.stderr ?? '', error: result.error?.message };
}

function recorder(artifactDir, execute, report) {
  const deadline = Date.now() + 1650_000;
  return (label, command, args, options = {}) => {
    const remaining = deadline - Date.now();
    assert.ok(remaining > 0, 'qualification deadline exhausted');
    const request = { command, args, cwd: artifactDir, env: cleanEnvironment(),
      ...options, timeoutMs: Math.min(options.timeoutMs ?? 120_000, remaining) };
    const result = execute(request);
    const stdout = path.join(artifactDir, `${report.commands.length}-${label}.stdout.log`);
    const stderr = path.join(artifactDir, `${report.commands.length}-${label}.stderr.log`);
    fs.writeFileSync(stdout, result.stdout ?? '');
    fs.writeFileSync(stderr, result.stderr ?? '');
    report.commands.push({ label, command, args, status: result.status,
      signal: result.signal ?? null, error: result.error ?? null, stdout, stderr,
      environment: options.env ? { PI_TEST_WRAPPER: options.env.PI_TEST_WRAPPER,
        PI_TEST_PACKAGE_DIR: options.env.PI_TEST_PACKAGE_DIR,
        PI_TEST_RELIABILITY_DIR: options.env.PI_TEST_RELIABILITY_DIR } : undefined });
    assert.ok(!result.error && !result.signal && result.status === 0,
      `${label} command failed (exit ${result.status}): ${result.error ?? result.stderr ?? ''}; log: ${stderr}`);
    return result;
  };
}

function parseJson(text) {
  try { return JSON.parse(text); }
  catch (cause) { throw new Error('Invalid JSON in qualification input', { cause }); }
}

export function compareProjection({ repo = repository, live, captured, run }) {
  const result = run('projection', 'python3', ['-B', '-c', projectionScript,
    path.join(repo, 'home/pi'), live, captured]);
  const projection = parseJson(result.stdout);
  assert.equal(projection.privateRuntimeExclusionsChecked, true);
  assert.equal(projection.equal, true, `stale managed projection: ${projection.changed.join(', ')}`);
  return projection;
}

// These selectors are derived from modules/homeManager/pi.nix:
// programs.pi-coding-agent.package = piWithPolicy; its launcher execs cfg.package.
export const evalApply = `host: let
  hm = host.config.home-manager.users.chetan;
  wrapper = hm.programs.pi-coding-agent.package;
  package = hm.cb.pi.package;
  in {
    system = host.pkgs.stdenv.hostPlatform.system;
    enabled = hm.cb.pi.enable && hm.programs.pi-coding-agent.enable;
    assertions = builtins.all (a: a.assertion) hm.assertions;
    wrapper = { drvPath = wrapper.drvPath; outputPath = wrapper.outPath; };
    package = { drvPath = package.drvPath; outputPath = package.outPath; };
  }`;

function verifyBuild(evaluation, builds, actualCommands) {
  assert.equal(evaluation.system, 'x86_64-linux', 'wrong Nix host platform');
  assert.equal(evaluation.enabled, true, 'Pi is not enabled on boris');
  assert.equal(evaluation.assertions, true, 'Home Manager assertions failed');
  for (const kind of ['wrapper', 'package']) {
    const expected = evaluation[kind];
    if (actualCommands) {
      assert.match(expected.drvPath, /^\/nix\/store\/[^/]+\.drv$/);
      assert.match(expected.outputPath, /^\/nix\/store\/[^/]+$/);
    } else {
      // Import-only fixture seam: fake outputs must stay in the fixture scratch tree.
      assert.match(expected.drvPath, /^\/tmp\/execution-strategy-tests\/.+\.drv$/);
      assert.match(expected.outputPath, /^\/tmp\/execution-strategy-tests\//);
    }
    assert.ok(builds.some(build => build.drvPath === expected.drvPath && build.outputs?.out === expected.outputPath),
      `build did not realize the evaluated ${kind} derivation`);
  }
}

function verifyExecutable(evaluation) {
  const wrapper = path.join(evaluation.wrapper.outputPath, 'bin/pi');
  const packageDir = path.join(evaluation.package.outputPath, 'lib/node_modules/pi-monorepo');
  fs.accessSync(wrapper, fs.constants.X_OK);
  assert.ok(fs.statSync(wrapper).isFile(), 'missing built executable');
  const text = fs.readFileSync(wrapper, 'utf8');
  assert.ok(text.includes(`${evaluation.package.outputPath}/bin/pi`), 'wrapper does not execute evaluated package');
  assert.ok(text.includes(packageDir), 'wrapper does not select evaluated SDK');
  assert.ok(fs.statSync(path.join(packageDir, 'dist/cli.js')).isFile(), 'missing built Pi CLI');
  // symlinkJoin may materialize directories while linking their individual files.
  assert.equal(fs.realpathSync(path.join(evaluation.wrapper.outputPath, 'lib/node_modules/pi-monorepo/dist/cli.js')),
    fs.realpathSync(path.join(packageDir, 'dist/cli.js')));
  return { wrapper, packageDir };
}

const requiredLauncherTests = [
  'test_cold_runtime_profile_can_report_version_without_packages',
  'test_cold_runtime_installs_then_repairs_before_real_rpc_import',
  'test_newly_installed_unknown_source_stops_before_rpc_import',
  'test_deferred_preflight_cannot_lose_its_selected_import_guard',
  'test_failed_preflight_stops_before_exec',
  'test_real_startup_disabled_settings_and_file_urls',
  'test_policy_reapplies_to_real_sdk_resource_reload',
  'test_incompatible_lens_interface_fails_closed',
];

function qualifyLauncher(run, evaluation, captured, repo, artifactDir) {
  const { wrapper, packageDir } = verifyExecutable(evaluation);
  const home = path.join(artifactDir, 'isolated-home');
  fs.mkdirSync(home);
  const env = { ...cleanEnvironment(), HOME: home, TMPDIR: artifactDir,
    XDG_CACHE_HOME: path.join(home, '.cache'), XDG_CONFIG_HOME: path.join(home, '.config'),
    PI_CODING_AGENT_DIR: path.join(home, '.pi/agent'), PI_OFFLINE: '1', PI_SKIP_VERSION_CHECK: '1',
    PI_TEST_WRAPPER: wrapper, PI_TEST_PACKAGE_DIR: packageDir,
    PI_TEST_RELIABILITY_DIR: path.join(captured, 'extensions/runtime-reliability') };
  const version = run('built-version', wrapper, ['--version'], { env, timeoutMs: 30_000 }).stdout.trim();
  assert.match(version, /^\d+\.\d+\.\d+$/);
  assert.equal(version, parseJson(fs.readFileSync(path.join(packageDir, 'package.json'), 'utf8')).version);
  const tests = run('launcher', 'python3', ['-B', '-m', 'unittest', 'discover',
    '-s', path.join(repo, 'home/pi'), '-p', 'test_pi_launcher.py', '-v'], { env, timeoutMs: 600_000 });
  const output = tests.stdout + tests.stderr;
  assert.match(output, /Ran [1-9]\d* tests? in/);
  assert.match(output, /\nOK\s*$/);
  assert.doesNotMatch(output, /\bskipped\b/i, 'launcher tests must not be skipped');
  for (const test of requiredLauncherTests) {
    assert.ok(output.split('\n').some(line => line.startsWith(`${test} (`) && line.endsWith(' ... ok')), `missing launcher regression: ${test}`);
  }
  return { wrapper, packageDir, version, requiredLauncherTests };
}

function sourceRevision(repo) {
  const inputs = ['flake.nix', 'flake.lock', 'hosts/boris/home.nix', 'hosts/boris/configuration.nix',
    'home/default.nix', 'home/pi/default.nix', 'home/pi/pi_config.py', 'home/pi/test_pi_launcher.py',
    'home/pi/execution-strategy-check.mjs', 'modules/homeManager/pi.nix',
    'modules/homeManager/pi-launcher.sh', 'modules/homeManager/pi-launcher-lens.mjs',
    'packages/pi-coding-agent.nix'];
  return Object.fromEntries(inputs.map(file => [file, createHash('sha256').update(fs.readFileSync(path.join(repo, file))).digest('hex')]));
}

// Injected execution is deliberately not an acceptance interface. It returns a
// fixture-only report and cannot print the CLI's real journey PASS.
export function checkQualification({ repo = repository, live, captured, artifactDir, execute = executeCommand }) {
  const report = { schemaVersion: 1, provenance: execute === executeCommand ? 'actual-commands' : 'fixture-only; NOT real-build evidence',
    host: 'boris', platform: 'x86_64-linux', selectors, repo, live, captured,
    activation: false, passed: false, commands: [] };
  const artifact = path.join(artifactDir, 'result.json');
  const run = recorder(artifactDir, execute, report);
  try {
    report.sourceRevision = sourceRevision(repo);
    report.projection = compareProjection({ repo, live, captured, run });
    const evaluated = run('nix-eval', 'nix', ['eval', '--json', '--no-write-lock-file',
      `${repo}#${selectors.host}`, '--apply', evalApply]);
    report.evaluation = JSON.parse(evaluated.stdout);
    assert.equal(report.evaluation.system, 'x86_64-linux', 'wrong Nix host platform');
    assert.equal(report.evaluation.enabled, true);
    assert.equal(report.evaluation.assertions, true);
    const built = run('nix-build', 'nix', ['build', '--json', '--no-link', '--no-write-lock-file',
      `${repo}#${selectors.wrapper}`, `${repo}#${selectors.package}`], { timeoutMs: 1200_000 });
    report.builds = JSON.parse(built.stdout);
    verifyBuild(report.evaluation, report.builds, execute === executeCommand);
    report.launcher = qualifyLauncher(run, report.evaluation, captured, repo, artifactDir);
    // Reject a mid-build live/capture change, even when both sides now match.
    assert.deepEqual(compareProjection({ repo, live, captured, run }), report.projection,
      'managed inputs changed during qualification');
    assert.deepEqual(sourceRevision(repo), report.sourceRevision, 'Nix/launcher sources changed during qualification');
    report.passed = true;
  } catch (error) {
    report.error = error.message;
  } finally {
    fs.writeFileSync(artifact, JSON.stringify(report, null, 2) + '\n');
  }
  return { report, artifact };
}

function main() {
  assert.equal(process.argv.length, 2, 'No flags accepted; fixtures are import-only and cannot qualify the live journey');
  const artifactDir = fs.mkdtempSync('/tmp/execution-strategy-check-');
  const { report, artifact } = checkQualification({ live: path.join(os.homedir(), '.pi/agent'),
    captured: path.join(here, 'config'), artifactDir });
  process.stdout.write(`Artifact: ${artifact}\n`);
  if (!report.passed) {
    // Keep the stale-projection failure easy to identify, without dumping values.
    const reason = report.error.includes('stale managed projection') ? 'stale managed projection' : report.error;
    process.stderr.write(`FAIL: live-capture: ${reason}\n`);
    process.exitCode = 1;
    return;
  }
  assert.equal(report.provenance, 'actual-commands');
  assert.equal(parseJson(fs.readFileSync(artifact, 'utf8')).passed, true);
  process.stdout.write(`${success}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
