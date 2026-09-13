// Fixture-only tests. No Nix build or live-capture evidence is produced here.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { checkQualification, compareProjection, evalApply, selectors } from './execution-strategy-check.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const base = '/tmp/execution-strategy-tests';
fs.mkdirSync(base, { recursive: true });
const suite = fs.mkdtempSync(path.join(base, 'fixture-'));
console.log(`Fixture artifacts (NOT real-build evidence): ${suite}`);

function json(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data));
}
function fixture() {
  const root = fs.mkdtempSync(path.join(suite, 'case-'));
  const live = path.join(root, 'live');
  const captured = path.join(root, 'captured');
  json(path.join(live, 'settings.json'), { theme: 'test', trackingId: 'runtime-only', lastChangelogVersion: '1' });
  json(path.join(captured, 'settings.json'), { theme: 'test' });
  json(path.join(live, 'profiles/pi-subagents/simple.json'), { fixture: true });
  json(path.join(captured, 'profiles/pi-subagents/simple.json'), { fixture: true });
  json(path.join(live, 'auth.json'), { fixture: 'excluded and never opened' });
  json(path.join(live, 'models-store.json'), { fixture: true });
  json(path.join(live, 'pi-codex-conversion.json'), { retired: true });
  fs.writeFileSync(path.join(captured, '.gitkeep'), '');
  const evaluation = { system: 'x86_64-linux', enabled: true, assertions: true,
    wrapper: { drvPath: path.join(root, 'wrapper.drv'), outputPath: path.join(root, 'wrapper') },
    package: { drvPath: path.join(root, 'package.drv'), outputPath: path.join(root, 'package') } };
  const packageDir = path.join(evaluation.package.outputPath, 'lib/node_modules/pi-monorepo');
  json(path.join(packageDir, 'package.json'), { version: '0.84.4', fixture: true });
  fs.mkdirSync(path.join(packageDir, 'dist'));
  fs.writeFileSync(path.join(packageDir, 'dist/cli.js'), '// fixture only\n');
  const wrapper = path.join(evaluation.wrapper.outputPath, 'bin/pi');
  fs.mkdirSync(path.dirname(wrapper), { recursive: true });
  fs.writeFileSync(wrapper, `#!/bin/sh\n# Fixture only; never launched by this suite.\n# ${packageDir}\nexec ${evaluation.package.outputPath}/bin/pi "$@"\n`, { mode: 0o755 });
  const joinedCli = path.join(evaluation.wrapper.outputPath, 'lib/node_modules/pi-monorepo/dist/cli.js');
  fs.mkdirSync(path.dirname(joinedCli), { recursive: true });
  fs.symlinkSync(path.join(packageDir, 'dist/cli.js'), joinedCli);
  const artifactDir = path.join(root, 'artifacts');
  fs.mkdirSync(artifactDir);
  const builds = ['wrapper', 'package'].map(kind => ({ drvPath: evaluation[kind].drvPath, outputs: { out: evaluation[kind].outputPath } }));
  const testNames = [...fs.readFileSync(path.join(here, 'test_pi_launcher.py'), 'utf8').matchAll(/^    def (test_\w+)\(/gm)].map(match => match[1]);
  const launcher = testNames.map(name => `${name} (fixture.PiLauncherTests.${name}) ... ok`).join('\n') + `\nRan ${testNames.length} tests in 1.0s\n\nOK\n`;
  const requests = [];
  const execute = request => {
    requests.push(request);
    const { command, args, cwd, env } = request;
    if (command === 'python3' && args.includes('-c')) {
      const result = spawnSync(command, args, { cwd, env, encoding: 'utf8' });
      return { status: result.status, stdout: result.stdout, stderr: result.stderr };
    }
    if (command === 'nix') return { status: 0, stdout: JSON.stringify(args[0] === 'eval' ? evaluation : builds), stderr: '' };
    if (command === wrapper) return { status: 0, stdout: '0.84.4\n', stderr: '' };
    if (command === 'python3' && args.includes('test_pi_launcher.py')) return { status: 0, stdout: '', stderr: launcher };
    throw new Error(`Unexpected fixture command: ${command}`);
  };
  return { root, repo, live, captured, artifactDir, evaluation, builds, wrapper, packageDir, launcher, requests, execute };
}
function projection(f) {
  return compareProjection({ ...f, run: (_label, command, args) => {
    const result = f.execute({ command, args, cwd: f.artifactDir, env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' } });
    assert.equal(result.status, 0, result.stderr);
    return result;
  } });
}
function rejected(f, pattern) {
  const result = checkQualification(f);
  assert.equal(result.report.passed, false);
  assert.match(result.report.error, pattern);
  assert.match(result.report.provenance, /^fixture-only/);
  assert.ok(fs.existsSync(result.artifact));
  assert.doesNotMatch(fs.readFileSync(result.artifact, 'utf8'), /PASS journey live-capture/);
  return result;
}

test('fixture success uses real projection semantics and exact host-selected commands, never real PASS', () => {
  const f = fixture();
  const result = checkQualification(f);
  assert.equal(result.report.passed, true, result.report.error);
  assert.match(result.report.provenance, /fixture-only; NOT real-build evidence/);
  assert.equal(result.report.activation, false);
  assert.equal(result.report.commands.length, 6);
  const build = f.requests.find(request => request.command === 'nix' && request.args[0] === 'build');
  assert.deepEqual(build.args, ['build', '--json', '--no-link', '--no-write-lock-file', `${repo}#${selectors.wrapper}`, `${repo}#${selectors.package}`]);
  assert.match(selectors.wrapper, /programs\.pi-coding-agent\.package$/);
  assert.match(selectors.package, /cb\.pi\.package$/);
  const launch = f.requests.find(request => request.args.includes('test_pi_launcher.py'));
  assert.equal(launch.env.PI_TEST_WRAPPER, f.wrapper);
  assert.equal(launch.env.PI_TEST_PACKAGE_DIR, f.packageDir);
  assert.equal(launch.env.PI_TEST_RELIABILITY_DIR, path.join(f.captured, 'extensions/runtime-reliability'));
  assert.equal(launch.env.HOME, path.join(f.artifactDir, 'isolated-home'));
  assert.doesNotMatch(fs.readFileSync(result.artifact, 'utf8'), /PASS journey live-capture/);
});

test('actual Nix JSON evaluation preserves both derivation fields without outPath coercion', () => {
  const expression = `{
    pkgs.stdenv.hostPlatform.system = "x86_64-linux";
    config.home-manager.users.chetan = {
      assertions = [{ assertion = true; }];
      programs.pi-coding-agent = { enable = true; package = { drvPath = "/nix/store/wrapper.drv"; outPath = "/nix/store/wrapper"; }; };
      cb.pi = { enable = true; package = { drvPath = "/nix/store/package.drv"; outPath = "/nix/store/package"; }; };
    };
  }`;
  const result = spawnSync('nix', ['eval', '--json', '--expr', expression, '--apply', evalApply], {
    cwd: suite, env: { PATH: process.env.PATH, HOME: suite, LANG: 'C.UTF-8' }, encoding: 'utf8', timeout: 30000,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.signal, null);
  const evaluated = JSON.parse(result.stdout);
  for (const kind of ['wrapper', 'package']) {
    assert.deepEqual(evaluated[kind], { drvPath: `/nix/store/${kind}.drv`, outputPath: `/nix/store/${kind}` });
  }
  // Actual evaluator over synthetic metadata only: no derivation was built here.
  fs.writeFileSync(path.join(suite, 'actual-nix-eval.json'), result.stdout);
});

for (const location of ['.gitkeep', 'profiles/.gitkeep']) {
  for (const kind of ['directory', 'symlink', 'nonempty-file']) {
    test(`raw capture rejects ${kind} at ${location}`, () => {
      const f = fixture();
      const placeholder = path.join(f.captured, location);
      if (location === '.gitkeep') fs.unlinkSync(placeholder);
      if (kind === 'directory') json(path.join(placeholder, 'auth.json'), { fixture: 'private' });
      else if (kind === 'symlink') fs.symlinkSync(path.join(f.live, 'auth.json'), placeholder);
      else fs.writeFileSync(placeholder, 'not an empty placeholder');
      rejected(f, /invalid captured \.gitkeep/);
      assert.equal(f.requests.length, 1);
    });
  }
}

test('raw capture permits empty regular nested .gitkeep placeholders', () => {
  const f = fixture();
  fs.writeFileSync(path.join(f.captured, 'profiles/.gitkeep'), '');
  assert.equal(projection(f).equal, true);
});

test('normalizes JSON, runtime settings, retired tombstones and non-executable permissions', () => {
  const f = fixture();
  fs.chmodSync(path.join(f.captured, 'settings.json'), 0o600);
  const result = projection(f);
  assert.equal(result.equal, true);
  assert.ok(result.excludedLiveNames.includes('auth.json'));
  assert.ok(result.excludedLiveNames.includes('pi-codex-conversion.json'));
  assert.equal(result.live['auth.json'], undefined);
});

test('stale managed projection fails before any Nix command', () => {
  const f = fixture();
  json(path.join(f.captured, 'settings.json'), { theme: 'stale' });
  rejected(f, /stale managed projection/);
  assert.equal(f.requests.length, 1);
});

test('executable permission differences are not normalized away', () => {
  const f = fixture();
  fs.chmodSync(path.join(f.captured, 'settings.json'), 0o700);
  rejected(f, /stale managed projection/);
});

for (const relative of ['auth.json', 'models-store.json', 'pi-codex-conversion.json', 'sessions/private.json',
  'extensions/pkg/node_modules/pkg/index.js', 'extensions/state/session.sqlite', 'skills/__pycache__/x.pyc']) {
  test(`rejects captured private/runtime artifact ${relative}`, () => {
    const f = fixture();
    json(path.join(f.captured, relative), { fixture: true });
    rejected(f, /private\/runtime|unmanaged/);
  });
}

test('rejects runtime settings even when normalized equality would pass', () => {
  const f = fixture();
  json(path.join(f.captured, 'settings.json'), { theme: 'test', trackingId: 'leaked' });
  rejected(f, /runtime settings leaked/);
});

test('rejects literal models secrets with existing projection validator', () => {
  const f = fixture();
  json(path.join(f.captured, 'models.json'), { providers: { fixture: { apiKey: 'fixture-literal-not-a-real-key' } } });
  rejected(f, /secret|apiKey/i);
});

test('rejects symlinks instead of following managed capture redirections', () => {
  const f = fixture();
  fs.symlinkSync(path.join(f.live, 'settings.json'), path.join(f.captured, 'profiles/redirect.json'));
  rejected(f, /symlink/);
});

for (const stage of ['projection', 'eval', 'build', 'version', 'launcher']) {
  test(`failed ${stage} command cannot qualify or run later steps`, () => {
    const f = fixture();
    const execute = f.execute;
    let reached = false;
    f.execute = request => {
      const match = stage === 'projection' ? request.args.includes('-c') : stage === 'version' ? request.command === f.wrapper :
        stage === 'launcher' ? request.args.includes('test_pi_launcher.py') : request.command === 'nix' && request.args[0] === stage;
      assert.equal(reached, false, 'a command ran after failure');
      if (match) { reached = true; return { status: 23, stdout: '', stderr: `fixture ${stage} failed` }; }
      return execute(request);
    };
    rejected(f, /command failed/);
    assert.equal(reached, true);
  });
}

test('command spawn errors and signals remain failures', () => {
  for (const result of [{ status: null, error: 'ENOENT' }, { status: null, signal: 'SIGTERM' }]) {
    const f = fixture();
    f.execute = () => result;
    rejected(f, /command failed/);
  }
});

test('an evaluated but unbuilt derivation is insufficient', () => {
  const f = fixture();
  f.builds.length = 0;
  rejected(f, /build did not realize/);
});

for (const failure of ['missing', 'not-executable', 'missing-cli', 'wrong-package']) {
  test(`${failure} built executable fails closed`, () => {
    const f = fixture();
    if (failure === 'missing') fs.unlinkSync(f.wrapper);
    if (failure === 'not-executable') fs.chmodSync(f.wrapper, 0o600);
    if (failure === 'missing-cli') fs.unlinkSync(path.join(f.packageDir, 'dist/cli.js'));
    if (failure === 'wrong-package') fs.writeFileSync(f.wrapper, '#!/bin/sh\nexit 0\n');
    rejected(f, /ENOENT|EACCES|wrapper does not execute/);
  });
}

test('wrong platform cannot build', () => {
  const f = fixture();
  f.evaluation.system = 'aarch64-darwin';
  rejected(f, /wrong Nix host platform/);
  assert.equal(f.requests.some(request => request.args[0] === 'build'), false);
});

for (const output of ['\nRan 0 tests in 0s\n\nOK\n', '\nRan 2 tests in 0s\n\nOK (skipped=2)\n', '\nRan 2 tests in 0s\n\nOK\n']) {
  test(`empty, skipped or incomplete launcher suite cannot qualify: ${output.trim()}`, () => {
    const f = fixture();
    const execute = f.execute;
    f.execute = request => request.args.includes('test_pi_launcher.py') ? { status: 0, stdout: '', stderr: output } : execute(request);
    rejected(f, /match|missing launcher regression|skipped/);
  });
}

test('mid-qualification projection change fails even if both sides match again', () => {
  const f = fixture();
  const execute = f.execute;
  f.execute = request => {
    if (request.args.includes('test_pi_launcher.py')) {
      for (const root of [f.live, f.captured]) json(path.join(root, 'settings.json'), { theme: 'new' });
    }
    return execute(request);
  };
  rejected(f, /managed inputs changed/);
});

test('CLI refuses fixture flags nonzero and never prints the real PASS', () => {
  const result = spawnSync(process.execPath, [path.join(here, 'execution-strategy-check.mjs'), '--fixture'], { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /No flags accepted/);
  assert.doesNotMatch(result.stdout + result.stderr, /PASS journey live-capture:/);
});
