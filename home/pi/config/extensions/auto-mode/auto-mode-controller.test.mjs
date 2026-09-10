import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createPublicKey, verify } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const extensionPath = fileURLToPath(new URL("./auto-mode-controller.ts", import.meta.url));
const entryPointPath = fileURLToPath(new URL("./index.ts", import.meta.url));
const jitiUrl = new URL("../../npm/node_modules/jiti/lib/jiti.mjs", import.meta.url);
const settingsPath = fileURLToPath(new URL("../../settings.json", import.meta.url));
const subagentConfigPath = fileURLToPath(
  new URL("../subagent/config.json", import.meta.url),
);
const controlEnvironment = "CB_PI_AUTO_MODE_CONTROL_V1";

function parseControlEnvironment(encoded = process.env[controlEnvironment]) {
  assert.ok(encoded, "auto-mode control environment must be published");
  const binding = JSON.parse(encoded);
  const publicKey = createPublicKey({
    key: Buffer.from(binding.publicKey, "base64url"),
    format: "der",
    type: "spki",
  });
  assert.equal(verifyControlRecord(binding.record, binding.session, publicKey), true);
  return { binding, publicKey };
}

function verifyControlRecord(record, session, publicKey) {
  if (record.session !== session) return false;
  const payload = Buffer.from(
    `${record.version}\n${record.session}\n${record.revision}\n${record.enabled ? "on" : "off"}`,
    "utf8",
  );
  return verify(null, payload, publicKey, Buffer.from(record.signature, "base64url"));
}

function controlRecordFromText(text) {
  const match = /<auto-mode-control payload="([A-Za-z0-9_-]+)">/.exec(text);
  assert.ok(match, "signed auto-mode marker must be present");
  return JSON.parse(Buffer.from(match[1], "base64url").toString("utf8"));
}

function createHarness(registerAutoMode) {
  const handlers = new Map();
  const commands = new Map();
  const sent = [];
  const notices = [];
  const statuses = new Map();
  let idle = true;
  let activeTools = ["read", "ask_user_question", "subagent"];
  let delegatedConfirmations = 0;
  const ui = {
    confirm: async () => {
      delegatedConfirmations += 1;
      return true;
    },
    notify: (message, level) => notices.push({ message, level }),
    setStatus: (key, text) => statuses.set(key, text),
    theme: { fg: (_color, text) => `[${text}]` },
  };
  const context = { isIdle: () => idle, ui };
  const pi = {
    getActiveTools: () => [...activeTools],
    getAllTools: () =>
      ["read", "ask_user_question", "subagent"].map((name) => ({ name })),
    on: (event, handler) => handlers.set(event, handler),
    registerCommand: (name, command) => commands.set(name, command),
    sendMessage: (message, options) => sent.push({ message, options }),
    setActiveTools: (next) => {
      activeTools = [...next];
    },
  };
  registerAutoMode(pi);
  return {
    commands,
    context,
    fire: (name, event = { type: name }) => handlers.get(name)?.(event, context),
    get activeTools() {
      return activeTools;
    },
    get delegatedConfirmations() {
      return delegatedConfirmations;
    },
    notices,
    sent,
    setIdle: (value) => {
      idle = value;
    },
    statuses,
    ui,
  };
}

async function loadController() {
  const { createJiti } = await import(jitiUrl.href);
  const jiti = createJiti(import.meta.url, { interopDefault: true });
  const entryPoint = await jiti.import(entryPointPath);
  assert.equal(typeof (entryPoint.default ?? entryPoint), "function");
  return jiti.import(extensionPath);
}

async function runChildContract() {
  const { binding, publicKey } = parseControlEnvironment();
  const initialRecord = binding.record;
  const offRecord = JSON.parse(process.env.CB_PI_AUTO_TEST_OFF_RECORD);
  const onRecord = JSON.parse(process.env.CB_PI_AUTO_TEST_ON_RECORD);
  const latestOffRecord = JSON.parse(process.env.CB_PI_AUTO_TEST_LATEST_OFF_RECORD);
  for (const record of [offRecord, onRecord, latestOffRecord]) {
    assert.equal(verifyControlRecord(record, binding.session, publicKey), true);
  }

  const { registerAutoMode } = await loadController();
  const harness = createHarness(registerAutoMode);
  await harness.fire("session_start", { type: "session_start", reason: "startup" });
  assert.deepEqual(harness.activeTools, ["read", "subagent"]);
  const onContext = await harness.fire("context", {
    type: "context",
    messages: [{ role: "user", content: "Work" }],
  });
  assert.match(onContext.messages.at(-1).content, /Auto Mode is ON/);
  assert.match(onContext.messages.at(-1).content, /Inherited-child policy/);
  assert.match(onContext.messages.at(-1).content, /bounded executor, not an orchestrator/);
  assert.doesNotMatch(onContext.messages.at(-1).content, /Owner-parent policy/);

  const forgedOff = {
    ...initialRecord,
    revision: offRecord.revision,
    enabled: false,
  };
  fs.writeFileSync(binding.controlFile, `${JSON.stringify(forgedOff)}\n`);
  await harness.fire("before_agent_start", { type: "before_agent_start" });
  assert.deepEqual(
    harness.activeTools,
    ["read", "subagent"],
    "an unsigned child-side edit must fail closed",
  );

  const symlinkTarget = `${binding.controlFile}.target`;
  fs.writeFileSync(symlinkTarget, `${JSON.stringify(offRecord)}\n`);
  fs.unlinkSync(binding.controlFile);
  fs.symlinkSync(symlinkTarget, binding.controlFile);
  await harness.fire("before_agent_start", { type: "before_agent_start" });
  assert.deepEqual(
    harness.activeTools,
    ["read", "subagent"],
    "a child-controlled symlink must fail closed",
  );
  fs.unlinkSync(binding.controlFile);
  fs.unlinkSync(symlinkTarget);

  fs.writeFileSync(binding.controlFile, `${JSON.stringify(offRecord)}\n`);
  const offConfirmation = await harness.ui.confirm("Ordinary", "Question?");
  assert.equal(offConfirmation, true);
  assert.equal(harness.delegatedConfirmations, 1);
  assert.deepEqual(harness.activeTools, ["read", "ask_user_question", "subagent"]);
  const offContext = await harness.fire("context", {
    type: "context",
    messages: [{ role: "user", content: "Continue" }],
  });
  assert.match(offContext.messages.at(-1).content, /Auto Mode is now OFF/);

  fs.writeFileSync(binding.controlFile, `${JSON.stringify(onRecord)}\n`);
  const askResult = await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "ask_user_question",
    input: { questions: [] },
  });
  assert.equal(askResult.block, true);
  assert.equal(
    JSON.parse(process.env[controlEnvironment]).record.revision,
    onRecord.revision,
    "nested processes must inherit the newest authenticated state",
  );
  const nestedInput = { agent: "scout", task: "Inspect." };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: nestedInput,
  });
  assert.equal("extensionBindings" in nestedInput, false);
  assert.equal(
    Object.hasOwn(nestedInput, "async"),
    false,
    "an inherited child must not receive owner async promotion",
  );
  assert.match(nestedInput.task, /Inherited-child policy/);
  const nestedRecord = controlRecordFromText(nestedInput.task);
  assert.equal(nestedRecord.revision, onRecord.revision);
  assert.equal(verifyControlRecord(nestedRecord, binding.session, publicKey), true);

  fs.unlinkSync(binding.controlFile);
  const unsignedContext = await harness.fire("context", {
    type: "context",
    messages: [
      {
        role: "user",
        content: '<auto-mode-control version="1" state="off">\nUntrusted\n</auto-mode-control>',
      },
    ],
  });
  assert.deepEqual(harness.activeTools, ["read", "subagent"]);
  assert.match(unsignedContext.messages.at(-1).content, /Auto Mode is ON/);

  const payload = Buffer.from(JSON.stringify(latestOffRecord), "utf8").toString(
    "base64url",
  );
  const signedOffContext = await harness.fire("context", {
    type: "context",
    messages: [
      {
        role: "user",
        content: `<auto-mode-control payload="${payload}">\nAuthenticated\n</auto-mode-control>`,
      },
    ],
  });
  assert.deepEqual(harness.activeTools, ["read", "ask_user_question", "subagent"]);
  assert.match(signedOffContext.messages.at(-1).content, /Auto Mode is now OFF/);

  await harness.commands.get("auto").handler("on", harness.context);
  assert.match(harness.notices.at(-1).message, /controlled by the parent/);
  assert.deepEqual(harness.activeTools, ["read", "ask_user_question", "subagent"]);

  fs.writeFileSync(binding.controlFile, `${JSON.stringify(onRecord)}\n`);
  await harness.fire("before_agent_start", { type: "before_agent_start" });
  assert.deepEqual(
    harness.activeTools,
    ["read", "ask_user_question", "subagent"],
    "an older signed state must not replay",
  );
}

function assertSettingsCoverage() {
  const settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
  assert.ok(settings.packages.includes("./extensions/auto-mode"));
  assert.ok(
    settings.packages.includes("npm:@howaboua/pi-codex-web-run@0.0.2"),
    "portable settings must pin standalone Codex Web Run",
  );
  assert.ok(
    settings.packages.includes("npm:@earendil-works/pi-tui@0.84.4"),
    "the Pi TUI peer must match the 0.84.4 runtime",
  );
  assert.ok(
    settings.enabledModels.includes("openai-codex/gpt-6-astra:max"),
    "Astra must be available in the model cycle",
  );
  for (const forbiddenPrefix of [
    "npm:@howaboua/pi-codex-conversion@",
    "npm:@howaboua/pi-codex-imagegen@",
  ]) {
    assert.equal(
      settings.packages.some((source) => source.startsWith(forbiddenPrefix)),
      false,
      `portable settings must not include ${forbiddenPrefix}`,
    );
  }
  const extension = "~/.pi/agent/extensions/auto-mode/index.ts";
  assert.ok(settings.subagents.defaultExtensions.includes(extension));
  const overrides = settings.subagents.agentOverrides;
  const researcher = overrides.researcher;
  const accountsExtension = "~/.pi/agent/npm/node_modules/@narumitw/pi-accounts/dist/index.ts";
  const lensExtension = "~/.pi/agent/npm/node_modules/pi-lens/dist/index.js";
  const webRunExtension = "~/.pi/agent/npm/node_modules/@howaboua/pi-codex-web-run/index.ts";
  const browserExtension =
    "~/.pi/agent/npm/node_modules/pi-agent-browser-native/dist/extensions/agent-browser/index.js";
  assert.deepEqual(
    researcher.extensions,
    [accountsExtension, lensExtension, webRunExtension],
    "researcher must load only accounts, Lens flags, and standalone Codex Web Run",
  );
  assert.equal(
    researcher.extensions.includes(browserExtension),
    false,
    "researcher must not load the native browser extension",
  );
  assert.deepEqual(
    researcher.tools,
    ["read", "web_run"],
    "researcher must keep its strict stateless research tools",
  );
  // This is a raw settings contract, not an imitation of pi-subagents' resolver.
  // With fork-only bridging, a fresh researcher must not receive contact_supervisor;
  // the required fresh-process smoke verifies the resolved launch.
  assert.equal(researcher.defaultContext, "fresh");
  assert.equal(researcher.tools.includes("contact_supervisor"), false);
  for (const forbiddenTool of ["agent_browser", "view_image"]) {
    assert.equal(
      researcher.tools.includes(forbiddenTool),
      false,
      `researcher must not expose ${forbiddenTool}`,
    );
  }
  for (const [name, override] of Object.entries(overrides)) {
    assert.ok(
      override.subagentOnlyExtensions.includes(extension),
      `${name} must load auto mode`,
    );
  }
  const terra = "openai-codex/gpt-5.6-terra";
  for (const name of ["researcher", "worker"]) {
    assert.equal(overrides[name].model, terra, `${name} must pin Terra`);
    assert.deepEqual(
      settings.subagents.modelScope.agents[name].allow,
      [terra],
      `${name} Terra pin must match its strict scope`,
    );
  }
  const researcherPrompt = overrides.researcher.systemPrompt;
  assert.equal(typeof researcherPrompt, "string", "researcher needs a system prompt");
  assert.equal(overrides.researcher.systemPromptMode, "append");
  assert.match(researcherPrompt, /\bweb_run\b/);
  assert.match(researcherPrompt, /\bsearch_query\b/);
  assert.match(researcherPrompt, /stateless one-angle web evidence specialist/i);
  assert.match(researcherPrompt, /Work only the assigned research angle/i);
  assert.match(
    researcherPrompt,
    /batch 2–4 high-signal `search_query` entries in one `web_run` call/i,
  );
  assert.match(researcherPrompt, /Prioritize primary sources, open the most relevant primary sources/i);
  assert.match(researcherPrompt, /cite final source URLs/i);
  assert.match(researcherPrompt, /After one setup, authentication, or provider failure, stop/i);
  assert.match(
    researcherPrompt,
    /Never use browser, shell, curl, or search-engine form automation/i,
  );
  assert.match(researcherPrompt, /Return compact evidence/i);
  assert.doesNotMatch(researcherPrompt, /\bagent_browser\b/i);
  assert.doesNotMatch(researcherPrompt, /\bview_image\b/i);
  for (const obsoleteName of [
    "web_search",
    "fetch_content",
    "get_search_content",
    "workflow",
  ]) {
    assert.doesNotMatch(
      researcherPrompt,
      new RegExp(`\\b${obsoleteName}\\b`, "i"),
      `researcher prompt must not reference unavailable ${obsoleteName}`,
    );
  }
  const oraclePrompt = overrides.oracle.systemPrompt;
  assert.equal(typeof oraclePrompt, "string", "oracle needs a system prompt");
  assert.equal(overrides.oracle.systemPromptMode, "append");
  assert.match(
    oraclePrompt,
    /In a fresh context, treat the supplied task and evidence as authoritative/i,
  );
  assert.match(
    oraclePrompt,
    /Only when the context is actually forked or those decisions are explicitly supplied/i,
  );
}

function assertSubagentConfigCoverage() {
  const config = JSON.parse(fs.readFileSync(subagentConfigPath, "utf8"));
  assert.deepEqual(config.intercomBridge, { mode: "fork-only", resultDelivery: false });
  assert.equal(config.artifactDir, "session");
  assert.equal(config.asyncByDefault, false);
  assert.equal(config.forceTopLevelAsync, false);
  assert.equal(config.globalConcurrencyLimit, 8);
  assert.equal(config.maxActiveAsyncRunsPerSession, 2);
  assert.equal(config.maxSubagentDepth, 1);
  assert.equal(config.maxSubagentSpawnsPerRun, 16);
  assert.equal(config.maxSubagentSpawnsPerSession, 64);
  assert.deepEqual(config.parallel, { concurrency: 8, maxTasks: 8 });
  assert.deepEqual(config.missions, {
    enabled: false,
    globalIndex: false,
    retainTerminal: 50,
  });
}

async function runParentContract() {
  assertSettingsCoverage();
  assertSubagentConfigCoverage();
  const { registerAutoMode } = await loadController();
  const harness = createHarness(registerAutoMode);
  await harness.fire("session_start", { type: "session_start", reason: "startup" });
  assert.deepEqual(harness.activeTools, ["read", "ask_user_question", "subagent"]);
  await harness.commands.get("auto").handler("status", harness.context);
  assert.match(harness.notices.at(-1).message, /Auto mode is OFF/);

  harness.setIdle(false);
  await harness.commands.get("auto").handler("on", harness.context);
  assert.deepEqual(harness.activeTools, ["read", "subagent"]);
  assert.equal(harness.statuses.get("cb-auto-mode"), "[AUTO]");
  assert.equal(harness.sent.length, 1);
  assert.equal(harness.sent[0].message.content, "Runtime Auto Mode transition.");
  assert.equal(harness.sent[0].options.deliverAs, "steer");
  const { binding, publicKey } = parseControlEnvironment();
  const fileRecord = JSON.parse(fs.readFileSync(binding.controlFile, "utf8"));
  assert.equal(fileRecord.enabled, true);
  assert.equal(verifyControlRecord(fileRecord, binding.session, publicKey), true);

  const askResult = await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "ask_user_question",
    input: { questions: [] },
  });
  assert.equal(askResult.block, true);

  const launchInput = { agent: "worker", task: "Implement the task." };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: launchInput,
  });
  assert.equal(launchInput.async, true, "owner launches default to async");
  assert.equal("extensionBindings" in launchInput, false);
  const launchRecord = controlRecordFromText(launchInput.task);
  assert.equal(launchRecord.enabled, true);
  assert.equal(verifyControlRecord(launchRecord, binding.session, publicKey), true);

  const explicitFalseInput = {
    agent: "worker",
    task: "Keep this foreground.",
    async: false,
  };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: explicitFalseInput,
  });
  assert.equal(explicitFalseInput.async, false, "explicit async false is preserved");

  const explicitTrueInput = {
    agent: "worker",
    task: "Keep this asynchronous.",
    async: true,
  };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: explicitTrueInput,
  });
  assert.equal(explicitTrueInput.async, true, "explicit async true is preserved");

  const foregroundOnlyInput = {
    agent: "worker",
    task: "Stay in the foreground.",
    foregroundOnly: true,
  };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: foregroundOnlyInput,
  });
  assert.equal(
    Object.hasOwn(foregroundOnlyInput, "async"),
    false,
    "foregroundOnly launches must not be promoted",
  );
  assert.equal(foregroundOnlyInput.foregroundOnly, true);

  const workflowSource =
    'return runs.run("resume", { resume: "retained-id", task: "Continue." })';
  const workflowInput = { workflowScript: workflowSource };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: workflowInput,
  });
  assert.equal(workflowInput.async, true, "owner workflows default to async");
  assert.equal(workflowInput.workflowScript, workflowSource, "workflow source is unchanged");
  assert.equal("extensionBindings" in workflowInput, false);

  const extensionBindings = {
    "existing-extension/1": { preserve: true },
  };
  const extensionBindingsBefore = structuredClone(extensionBindings);
  const extensionBindingsInput = {
    agent: "worker",
    task: "Retain bindings.",
    extensionBindings,
  };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: extensionBindingsInput,
  });
  assert.strictEqual(
    extensionBindingsInput.extensionBindings,
    extensionBindings,
    "extension bindings object reference is preserved",
  );
  assert.deepEqual(
    extensionBindingsInput.extensionBindings,
    extensionBindingsBefore,
    "extension bindings contents are not mutated",
  );

  const managementInput = {
    action: "list",
    agent: "worker",
    task: "Do not launch.",
  };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: managementInput,
  });
  assert.equal(Object.hasOwn(managementInput, "async"), false);
  assert.equal(managementInput.task, "Do not launch.");

  const scheduleInput = {
    action: "schedule.create",
    every: "6h",
    workflowScript: workflowSource,
  };
  const scheduleInputBefore = structuredClone(scheduleInput);
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: scheduleInput,
  });
  assert.deepEqual(scheduleInput, scheduleInputBefore, "schedule input is not mutated");

  const steerInput = { action: "steer", id: "run-1", message: "Steer." };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: steerInput,
  });
  assert.equal(Object.hasOwn(steerInput, "async"), false);
  const steerRecord = controlRecordFromText(steerInput.message);
  assert.equal(steerRecord.enabled, true);
  assert.equal(verifyControlRecord(steerRecord, binding.session, publicKey), true);

  const activeResumeInput = {
    action: "resume",
    id: "run-1",
    message: "Continue.",
  };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: activeResumeInput,
  });
  assert.equal(Object.hasOwn(activeResumeInput, "async"), false);
  const activeResumeRecord = controlRecordFromText(activeResumeInput.message);
  assert.equal(activeResumeRecord.enabled, true);
  assert.equal(
    verifyControlRecord(activeResumeRecord, binding.session, publicKey),
    true,
  );

  await harness.fire("tool_execution_start", {
    type: "tool_execution_start",
    toolCallId: "grant-1",
    toolName: "subagent",
    args: { action: "grant-spawn-budget", additional: 3 },
  });
  const suffix =
    "Usage is not reset. Compaction keeps the same budget; a new parent session starts a fresh one.";
  assert.equal(
    await harness.ui.confirm(
      "Grant subagent spawn budget?",
      `Add 3 launches to this logical session?\n\n${suffix}`,
    ),
    false,
  );
  assert.equal(
    await harness.ui.confirm(
      "Grant subagent spawn budget?",
      `Add 3 launches to this logical session?\n\nSpawn budget: arbitrary\n\n${suffix}`,
    ),
    false,
  );
  assert.equal(
    await harness.ui.confirm(
      "Grant subagent spawn budget?",
      `Add 3 launches to this logical session?\n\nSpawn budget: 8/10 used, 9 remaining (configured 8; granted 2; grant allowance 6)\n\n${suffix}`,
    ),
    false,
  );
  assert.equal(
    await harness.ui.confirm(
      "Grant subagent spawn budget?",
      `Add 3 launches to this logical session?\n\nSpawn budget: 8/10 used, 2 remaining (configured 8; granted 2; grant allowance 6)\n\n${suffix}`,
    ),
    true,
  );
  assert.equal(await harness.ui.confirm("Delete everything?", "Really?"), false);
  assert.equal(harness.delegatedConfirmations, 0);

  const activeContext = await harness.fire("context", {
    type: "context",
    messages: [
      { role: "user", content: "Continue." },
      {
        role: "custom",
        customType: "cb-auto-mode-transition",
        content: "old",
        display: false,
      },
    ],
  });
  assert.equal(
    activeContext.messages.some(
      (message) => message.customType === "cb-auto-mode-transition",
    ),
    false,
  );
  assert.match(activeContext.messages.at(-1).content, /Auto Mode is ON/);
  assert.match(activeContext.messages.at(-1).content, /Owner-parent policy/);
  assert.match(activeContext.messages.at(-1).content, /orchestrator and final authority/);
  assert.doesNotMatch(activeContext.messages.at(-1).content, /Inherited-child policy/);

  await harness.commands.get("auto").handler("off", harness.context);
  assert.deepEqual(harness.activeTools, ["read", "ask_user_question", "subagent"]);
  assert.equal(harness.sent.length, 2);
  assert.equal(harness.sent[1].message.content, "Runtime Auto Mode transition.");

  const offLaunchInput = { agent: "worker", task: "Work while Auto Mode is off." };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: offLaunchInput,
  });
  assert.equal(
    Object.hasOwn(offLaunchInput, "async"),
    false,
    "OFF mode launches must not be promoted",
  );
  assert.equal(offLaunchInput.task, "Work while Auto Mode is off.");

  const offContext = await harness.fire("context", {
    type: "context",
    messages: [
      { role: "user", content: "Original task" },
      {
        role: "custom",
        customType: "cb-auto-mode-transition",
        content: "stale ON prose",
        display: false,
      },
      {
        role: "custom",
        customType: "cb-auto-mode-instructions",
        content: "stale instructions",
        display: false,
      },
    ],
  });
  assert.equal(offContext.messages.length, 2);
  assert.equal(offContext.messages[0].content, "Original task");
  assert.match(offContext.messages[1].content, /Auto Mode is now OFF/);
  const laterContext = await harness.fire("context", {
    type: "context",
    messages: offContext.messages,
  });
  assert.deepEqual(laterContext.messages, [{ role: "user", content: "Original task" }]);

  const resumeInput = { action: "resume", id: "run-1", message: "Continue." };
  await harness.fire("tool_call", {
    type: "tool_call",
    toolName: "subagent",
    input: resumeInput,
  });
  assert.equal(Object.hasOwn(resumeInput, "async"), false);
  const resumeRecord = controlRecordFromText(resumeInput.message);
  assert.equal(resumeRecord.enabled, false);
  assert.equal(verifyControlRecord(resumeRecord, binding.session, publicKey), true);
  assert.equal(await harness.ui.confirm("Ordinary", "Question"), true);
  assert.equal(harness.delegatedConfirmations, 1);

  harness.setIdle(true);
  await harness.commands.get("auto").handler("on", harness.context);
  const childBindingEncoded = process.env[controlEnvironment];
  const childInitialRecord = JSON.parse(fs.readFileSync(binding.controlFile, "utf8"));
  await harness.fire("session_shutdown", { type: "session_shutdown", reason: "reload" });
  assert.deepEqual(harness.activeTools, ["read", "ask_user_question", "subagent"]);
  assert.equal(await harness.ui.confirm("During reload", "Question"), true);
  await harness.fire("session_start", { type: "session_start", reason: "reload" });
  assert.deepEqual(harness.activeTools, ["read", "subagent"]);
  assert.equal(await harness.ui.confirm("After reload", "Question"), false);

  await harness.commands.get("auto").handler("off", harness.context);
  const childOffRecord = JSON.parse(fs.readFileSync(binding.controlFile, "utf8"));
  await harness.commands.get("auto").handler("on", harness.context);
  const childOnRecord = JSON.parse(fs.readFileSync(binding.controlFile, "utf8"));
  await harness.commands.get("auto").handler("off", harness.context);
  const childLatestOffRecord = JSON.parse(fs.readFileSync(binding.controlFile, "utf8"));
  assert.ok(childInitialRecord.revision < childOffRecord.revision);
  assert.ok(childOffRecord.revision < childOnRecord.revision);
  assert.ok(childOnRecord.revision < childLatestOffRecord.revision);
  fs.writeFileSync(binding.controlFile, `${JSON.stringify(childInitialRecord)}\n`);
  assert.equal(harness.sent.length, 2, "idle toggles must not create model turns");

  return {
    bindingEncoded: childBindingEncoded,
    childOffRecord,
    childOnRecord,
    childLatestOffRecord,
    controlDirectory: path.dirname(binding.controlFile),
    shutdown: () =>
      harness.fire("session_shutdown", { type: "session_shutdown", reason: "quit" }),
  };
}

if (process.argv.includes("--child")) {
  await runChildContract();
  console.log("auto-mode child propagation: ok");
} else {
  const ambientControl = process.env[controlEnvironment];
  delete process.env[controlEnvironment];
  let contract;
  try {
    contract = await runParentContract();
    const controlDirectory = contract.controlDirectory;
    const child = spawnSync(process.execPath, [fileURLToPath(import.meta.url), "--child"], {
      encoding: "utf8",
      env: {
        ...process.env,
        [controlEnvironment]: contract.bindingEncoded,
        CB_PI_AUTO_TEST_OFF_RECORD: JSON.stringify(contract.childOffRecord),
        CB_PI_AUTO_TEST_ON_RECORD: JSON.stringify(contract.childOnRecord),
        CB_PI_AUTO_TEST_LATEST_OFF_RECORD: JSON.stringify(
          contract.childLatestOffRecord,
        ),
      },
    });
    await contract.shutdown();
    contract = undefined;
    assert.equal(fs.existsSync(controlDirectory), false);
    assert.equal(child.status, 0, child.stderr || child.stdout);
    process.stdout.write(child.stdout);
    console.log("auto-mode parent contract: ok");
  } finally {
    if (contract) await contract.shutdown();
    if (ambientControl === undefined) {
      delete process.env[controlEnvironment];
    } else {
      process.env[controlEnvironment] = ambientControl;
    }
  }
}
