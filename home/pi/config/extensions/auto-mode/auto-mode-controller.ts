import {
  createPublicKey,
  generateKeyPairSync,
  randomUUID,
  sign,
  verify,
  type KeyObject,
} from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const ASK_USER_TOOL = "ask_user_question";
const SUBAGENT_TOOL = "subagent";
const AUTO_STATUS_KEY = "cb-auto-mode";
const AUTO_MODE_CONTROL_ENV = "CB_PI_AUTO_MODE_CONTROL_V1";
const AUTO_MODE_CONTROL_VERSION = 1;
const SPAWN_BUDGET_TITLE = "Grant subagent spawn budget?";
const SPAWN_BUDGET_SUFFIX =
  "Usage is not reset. Compaction keeps the same budget; a new parent session starts a fresh one.";

const AUTO_MODE_INSTRUCTIONS = `<auto-mode>
Unattended Auto Mode is ON for this Pi process.
- Continue the current task without asking the user questions or waiting for user input.
- Do not call ask_user_question or ask for clarification in prose.
- Resolve ambiguity from available context. Prefer the safest reversible choice. If a decision is not safely inferable, skip only that blocked action, record the assumption or blocker, and continue all independent work.
- Spawn-budget increases requested through pi-subagents are authorized and will be approved automatically.
- Other interactive confirmations are denied; adapt by taking a safe, non-destructive path.
- Child Pi processes inherit this runtime mode automatically. Include these constraints in child task contracts and resolve child clarification requests yourself instead of relaying them to the user.
- Auto Mode does not authorize destructive, security-sensitive, privacy-sensitive, production, purchase, publication, merge, release, or account changes unless the user already authorized them explicitly.
</auto-mode>`;

const AUTO_MODE_OFF_INSTRUCTIONS = `<auto-mode>
Unattended Auto Mode is now OFF for this Pi process. Resume normal interactive behavior and ask the user when a decision genuinely requires their input.
</auto-mode>`;

const AUTO_MODE_TRANSITION_WAKE = "Runtime Auto Mode transition.";
const AUTO_MODE_TRANSITION_MESSAGE_TYPE = "cb-auto-mode-transition";
const AUTO_MODE_INSTRUCTION_MESSAGE_TYPE = "cb-auto-mode-instructions";
const AUTO_MODE_CONTROL_MARKER = /<auto-mode-control payload="([A-Za-z0-9_-]+)">/g;

interface ControlRecord {
  version: 1;
  session: string;
  revision: number;
  enabled: boolean;
  signature: string;
}

interface InheritedControl {
  controlFile: string;
  session: string;
  publicKey: KeyObject;
  publicKeyDer: string;
  record: ControlRecord;
}

interface RuntimeState {
  protocol: 2;
  enabled: boolean;
  /** Undefined means this session's baseline has not been captured. */
  askToolIndex?: number;
  /** Delivers the OFF instruction exactly once to an already-running turn. */
  pendingOffInstruction: boolean;
  /** Authenticated runtime state shared with descendant Pi processes. */
  controlFile: string;
  ownsControlFile: boolean;
  session: string;
  revision: number;
  record: ControlRecord;
  publicKey: KeyObject;
  publicKeyDer: string;
  privateKey?: KeyObject;
  previousControlEnvironment?: string;
}

interface ExtensionDialogOptions {
  signal?: AbortSignal;
  timeout?: number;
}

interface ExtensionUi {
  confirm(
    title: string,
    message: string,
    options?: ExtensionDialogOptions,
  ): Promise<boolean>;
  notify(message: string, level?: "info" | "warning" | "error"): void;
  setStatus(key: string, text: string | undefined): void;
  theme: {
    fg(color: string, text: string): string;
  };
}

export interface ExtensionContext {
  isIdle(): boolean;
  ui: ExtensionUi;
}

interface SessionStartEvent {
  type: "session_start";
  reason: "startup" | "reload" | "new" | "resume" | "fork";
}

interface SessionShutdownEvent {
  type: "session_shutdown";
  reason: "quit" | "reload" | "new" | "resume" | "fork";
}

interface BeforeAgentStartEvent {
  type: "before_agent_start";
}

interface TextContentPart {
  type?: string;
  text?: string;
}

interface ContextMessage {
  role?: string;
  customType?: string;
  content?: string | TextContentPart[];
  display?: boolean;
  timestamp?: number;
}

interface ContextEvent {
  type: "context";
  messages: ContextMessage[];
}

interface ToolCallEvent {
  type: "tool_call";
  toolName: string;
  input: Record<string, unknown>;
}

interface SubagentToolArgs {
  action?: string;
  additional?: number;
}

interface ToolExecutionStartEvent {
  type: "tool_execution_start";
  toolCallId: string;
  toolName: string;
  args?: SubagentToolArgs;
}

interface ToolExecutionEndEvent {
  type: "tool_execution_end";
  toolCallId: string;
}

interface ToolCallResult {
  block: true;
  reason: string;
}

interface ContextEventResult {
  messages: ContextMessage[];
}

type MaybePromise<T> = T | Promise<T>;
type EventHandler<Event, Result = void> = (
  event: Event,
  context: ExtensionContext,
) => MaybePromise<Result | void>;

export interface ExtensionApi {
  getActiveTools(): string[];
  getAllTools(): Array<{ name: string }>;
  on(event: "session_start", handler: EventHandler<SessionStartEvent>): void;
  on(
    event: "before_agent_start",
    handler: EventHandler<BeforeAgentStartEvent>,
  ): void;
  on(event: "context", handler: EventHandler<ContextEvent, ContextEventResult>): void;
  on(event: "tool_call", handler: EventHandler<ToolCallEvent, ToolCallResult>): void;
  on(
    event: "tool_execution_start",
    handler: EventHandler<ToolExecutionStartEvent>,
  ): void;
  on(
    event: "tool_execution_end",
    handler: EventHandler<ToolExecutionEndEvent>,
  ): void;
  on(event: "session_shutdown", handler: EventHandler<SessionShutdownEvent>): void;
  registerCommand(
    name: string,
    command: {
      description: string;
      getArgumentCompletions?: (
        prefix: string,
      ) => Array<{ value: string; label: string }> | null;
      handler: (args: string, context: ExtensionContext) => MaybePromise<void>;
    },
  ): void;
  sendMessage(
    message: {
      customType: string;
      content: string;
      display: boolean;
    },
    options?: {
      triggerTurn?: boolean;
      deliverAs?: "steer" | "followUp" | "nextTurn";
    },
  ): void;
  setActiveTools(toolNames: string[]): void;
}

interface ConfirmBinding {
  ui: ExtensionUi;
  original: ExtensionUi["confirm"];
  wrapped: ExtensionUi["confirm"];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function controlPayload(record: Omit<ControlRecord, "signature">): Buffer {
  return Buffer.from(
    `${record.version}\n${record.session}\n${record.revision}\n${record.enabled ? "on" : "off"}`,
    "utf8",
  );
}

function signControlRecord(
  privateKey: KeyObject,
  session: string,
  revision: number,
  enabled: boolean,
): ControlRecord {
  const unsigned = {
    version: AUTO_MODE_CONTROL_VERSION,
    session,
    revision,
    enabled,
  } as const;
  return {
    ...unsigned,
    signature: sign(null, controlPayload(unsigned), privateKey).toString("base64url"),
  };
}

function decodeControlRecord(
  value: unknown,
  session: string,
  publicKey: KeyObject,
): ControlRecord | undefined {
  if (
    !isRecord(value) ||
    value.version !== AUTO_MODE_CONTROL_VERSION ||
    value.session !== session ||
    !Number.isSafeInteger(value.revision) ||
    (value.revision as number) < 0 ||
    typeof value.enabled !== "boolean" ||
    typeof value.signature !== "string" ||
    !/^[A-Za-z0-9_-]+$/.test(value.signature)
  ) {
    return undefined;
  }
  const record: ControlRecord = {
    version: AUTO_MODE_CONTROL_VERSION,
    session,
    revision: value.revision as number,
    enabled: value.enabled,
    signature: value.signature,
  };
  try {
    return verify(
      null,
      controlPayload(record),
      publicKey,
      Buffer.from(record.signature, "base64url"),
    )
      ? record
      : undefined;
  } catch {
    return undefined;
  }
}

function readInheritedControl(): InheritedControl | undefined {
  const encoded = process.env[AUTO_MODE_CONTROL_ENV];
  if (!encoded) return undefined;
  try {
    const value: unknown = JSON.parse(encoded);
    if (
      !isRecord(value) ||
      value.version !== AUTO_MODE_CONTROL_VERSION ||
      typeof value.session !== "string" ||
      !/^[0-9a-f-]{36}$/i.test(value.session) ||
      typeof value.controlFile !== "string" ||
      !path.isAbsolute(value.controlFile) ||
      typeof value.publicKey !== "string" ||
      !/^[A-Za-z0-9_-]+$/.test(value.publicKey)
    ) {
      return undefined;
    }
    const publicKey = createPublicKey({
      key: Buffer.from(value.publicKey, "base64url"),
      format: "der",
      type: "spki",
    });
    const record = decodeControlRecord(value.record, value.session, publicKey);
    if (!record) return undefined;
    return {
      controlFile: value.controlFile,
      session: value.session,
      publicKey,
      publicKeyDer: value.publicKey,
      record,
    };
  } catch {
    return undefined;
  }
}

function defaultControlFile(): string {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "cb-pi-auto-mode-"));
  return path.join(directory, "state.json");
}

function createOwnedState(): RuntimeState {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const session = randomUUID();
  const publicKeyDer = publicKey.export({ format: "der", type: "spki" }).toString("base64url");
  const record = signControlRecord(privateKey, session, 0, false);
  return {
    protocol: 2,
    enabled: false,
    pendingOffInstruction: false,
    controlFile: defaultControlFile(),
    ownsControlFile: true,
    session,
    revision: record.revision,
    record,
    publicKey,
    publicKeyDer,
    privateKey,
    previousControlEnvironment: process.env[AUTO_MODE_CONTROL_ENV],
  };
}

function createInheritedState(control: InheritedControl): RuntimeState {
  return {
    protocol: 2,
    enabled: control.record.enabled,
    pendingOffInstruction: false,
    controlFile: control.controlFile,
    ownsControlFile: false,
    session: control.session,
    revision: control.record.revision,
    record: control.record,
    publicKey: control.publicKey,
    publicKeyDer: control.publicKeyDer,
  };
}

function encodedControlBinding(): string {
  return JSON.stringify({
    version: AUTO_MODE_CONTROL_VERSION,
    session: state.session,
    controlFile: state.controlFile,
    publicKey: state.publicKeyDer,
    record: state.record,
  });
}

function writeOwnedState(): void {
  if (!state.ownsControlFile) return;
  const directory = path.dirname(state.controlFile);
  const temporary = `${state.controlFile}.${process.pid}.tmp`;
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  fs.writeFileSync(temporary, `${JSON.stringify(state.record)}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
  fs.renameSync(temporary, state.controlFile);
  process.env[AUTO_MODE_CONTROL_ENV] = encodedControlBinding();
}

function updateOwnedState(enabled: boolean): void {
  if (!state.ownsControlFile || !state.privateKey) return;
  state.revision += 1;
  state.record = signControlRecord(
    state.privateKey,
    state.session,
    state.revision,
    enabled,
  );
  state.enabled = enabled;
  writeOwnedState();
}

function readControlFile(): ControlRecord | undefined {
  try {
    const metadata = fs.lstatSync(state.controlFile);
    if (!metadata.isFile() || metadata.size > 16_384) return undefined;
    const parsed: unknown = JSON.parse(fs.readFileSync(state.controlFile, "utf8"));
    return decodeControlRecord(parsed, state.session, state.publicKey);
  } catch {
    return undefined;
  }
}

function acceptControlRecord(record: ControlRecord | undefined): boolean {
  if (!record || record.revision < state.revision) return false;
  if (
    record.revision === state.revision &&
    record.signature !== state.record.signature
  ) {
    return false;
  }
  state.revision = record.revision;
  state.record = record;
  state.enabled = record.enabled;
  process.env[AUTO_MODE_CONTROL_ENV] = encodedControlBinding();
  return true;
}

const runtimeGlobal = globalThis as typeof globalThis & {
  __cbPiAutoModeV2?: RuntimeState;
};
const existingState = runtimeGlobal.__cbPiAutoModeV2;
const inheritedControl = existingState ? undefined : readInheritedControl();
const state = (runtimeGlobal.__cbPiAutoModeV2 ??= inheritedControl
  ? createInheritedState(inheritedControl)
  : createOwnedState());

function refreshInheritedState(): boolean {
  if (state.ownsControlFile) return true;
  const record = readControlFile();
  if (!record) return false;
  acceptControlRecord(record);
  return true;
}

function controlMarker(record: ControlRecord): string {
  const payload = Buffer.from(JSON.stringify(record), "utf8").toString("base64url");
  return `<auto-mode-control payload="${payload}">`;
}

function childTransitionInstructions(enabled: boolean): string {
  const instruction = enabled
    ? "The parent Pi process enabled unattended Auto Mode. Do not ask the user or pause for user input. Resolve ambiguity from context using the safest reversible choice, report assumptions, and continue independent work. Escalate only destructive or otherwise unauthorized actions to the parent."
    : "The parent Pi process disabled unattended Auto Mode. Resume the normal child-agent clarification and supervisor-coordination policy.";
  return `${controlMarker(state.record)}\n${instruction}\n</auto-mode-control>`;
}

function applyInheritedTransition(
  runtime: AutoModeRuntime,
  wasEnabled: boolean,
): void {
  if (state.enabled === wasEnabled) return;
  if (state.enabled) {
    state.pendingOffInstruction = false;
    suppressAskTool(runtime);
  } else {
    state.pendingOffInstruction = true;
    restoreAskToolAndForgetBaseline(runtime);
  }
}

function syncInheritedRuntime(runtime: AutoModeRuntime): boolean {
  const wasEnabled = state.enabled;
  const controlFileAvailable = refreshInheritedState();
  if (!state.ownsControlFile) applyInheritedTransition(runtime, wasEnabled);
  return controlFileAvailable;
}
interface AutoModeRuntime {
  pi: ExtensionApi;
  pendingSpawnBudgetGrants: Map<string, number>;
  confirmBinding?: ConfirmBinding;
}

export function registerAutoMode(pi: ExtensionApi): void {
  refreshInheritedState();
  writeOwnedState();
  const runtime: AutoModeRuntime = {
    pi,
    pendingSpawnBudgetGrants: new Map<string, number>(),
  };
  registerCommand(runtime);
  registerEventHandlers(runtime);
}

function registerCommand(runtime: AutoModeRuntime): void {
  runtime.pi.registerCommand("auto", {
    description: "Toggle unattended mode for this Pi process",
    getArgumentCompletions,
    handler: (args, context) => handleCommand(runtime, args, context),
  });
}

function registerEventHandlers(runtime: AutoModeRuntime): void {
  runtime.pi.on("session_start", (event, context) =>
    handleSessionStart(runtime, event, context),
  );
  runtime.pi.on("before_agent_start", () => {
    syncInheritedRuntime(runtime);
    handleBeforeAgentStart(runtime);
  });
  runtime.pi.on("context", (event) => handleContext(runtime, event));
  runtime.pi.on("tool_call", (event) => handleToolCall(runtime, event));
  runtime.pi.on("tool_execution_start", (event) =>
    trackConfirmationStart(runtime, event),
  );
  runtime.pi.on("tool_execution_end", (event) => {
    runtime.pendingSpawnBudgetGrants.delete(event.toolCallId);
  });
  runtime.pi.on("session_shutdown", (event, context) =>
    handleSessionShutdown(runtime, event, context),
  );
}

function getArgumentCompletions(
  prefix: string,
): Array<{ value: string; label: string }> | null {
  const choices = ["on", "off", "status"];
  const normalizedPrefix = prefix.trim().toLowerCase();
  const matches = choices.filter((choice) => choice.startsWith(normalizedPrefix));
  return matches.length > 0
    ? matches.map((choice) => ({ value: choice, label: choice }))
    : null;
}

function handleCommand(
  runtime: AutoModeRuntime,
  args: string,
  context: ExtensionContext,
): void {
  const action = args.trim().toLowerCase();
  if (!state.ownsControlFile && action !== "status") {
    context.ui.notify(
      "Auto mode is controlled by the parent Pi process for this child session.",
      "warning",
    );
    return;
  }
  switch (action) {
    case "status":
      syncInheritedRuntime(runtime);
      showStatus(context);
      return;
    case "":
    case "toggle":
      state.enabled ? disable(runtime, context) : enable(runtime, context);
      return;
    case "on":
    case "enable":
    case "enabled":
      enable(runtime, context);
      return;
    case "off":
    case "disable":
    case "disabled":
      disable(runtime, context);
      return;
    default:
      context.ui.notify("Usage: /auto [on|off|status]", "error");
  }
}

function showStatus(context: ExtensionContext): void {
  updateStatus(context.ui);
  context.ui.notify(
    state.enabled
      ? "Auto mode is ON: questions suppressed, spawn-budget grants approved, other confirmations denied."
      : "Auto mode is OFF: normal interactive behavior is active.",
    "info",
  );
}

function enable(runtime: AutoModeRuntime, context: ExtensionContext): void {
  if (state.enabled) {
    updateStatus(context.ui);
    context.ui.notify("Auto mode is already ON.", "info");
    return;
  }

  updateOwnedState(true);
  state.pendingOffInstruction = false;
  suppressAskTool(runtime);
  updateStatus(context.ui);
  sendTransitionToActiveRun(runtime, context);
  context.ui.notify(
    "Auto mode ON: questions suppressed, spawn-budget grants approved, other confirmations denied.",
    "warning",
  );
}

function disable(runtime: AutoModeRuntime, context: ExtensionContext): void {
  if (!state.enabled) {
    updateStatus(context.ui);
    context.ui.notify("Auto mode is already OFF.", "info");
    return;
  }

  state.pendingOffInstruction = !context.isIdle();
  updateOwnedState(false);
  restoreAskToolAndForgetBaseline(runtime);
  updateStatus(context.ui);
  sendTransitionToActiveRun(runtime, context);
  context.ui.notify(
    "Auto mode OFF: interactive questions and confirmations restored.",
    "info",
  );
}

function handleSessionStart(
  runtime: AutoModeRuntime,
  event: SessionStartEvent,
  context: ExtensionContext,
): void {
  syncInheritedRuntime(runtime);
  installConfirmWrapper(runtime, context.ui);
  if (event.reason !== "reload") {
    resetAskToolBaseline();
  }
  if (state.enabled) {
    suppressAskTool(runtime);
  }
  updateStatus(context.ui);
}

function handleBeforeAgentStart(runtime: AutoModeRuntime): void {
  if (state.enabled) {
    suppressAskTool(runtime);
  }
}

function messageText(message: ContextMessage): string {
  if (typeof message.content === "string") return message.content;
  if (!message.content) return "";
  return message.content
    .map((part) => (part.type === "text" ? (part.text ?? "") : ""))
    .join("\n");
}

function latestChildControl(
  messages: ContextMessage[],
): ControlRecord | undefined {
  let latest: ControlRecord | undefined;
  for (const message of messages) {
    const text = messageText(message);
    AUTO_MODE_CONTROL_MARKER.lastIndex = 0;
    for (const match of text.matchAll(AUTO_MODE_CONTROL_MARKER)) {
      const payload = match[1];
      if (!payload) continue;
      try {
        const parsed: unknown = JSON.parse(
          Buffer.from(payload, "base64url").toString("utf8"),
        );
        const record = decodeControlRecord(parsed, state.session, state.publicKey);
        if (record && (!latest || record.revision > latest.revision)) {
          latest = record;
        }
      } catch {
        // Ignore malformed or unauthenticated task text.
      }
    }
  }
  return latest;
}

function isManagedContextMessage(message: ContextMessage): boolean {
  return (
    message.customType === AUTO_MODE_TRANSITION_MESSAGE_TYPE ||
    message.customType === AUTO_MODE_INSTRUCTION_MESSAGE_TYPE
  );
}

function handleContext(
  runtime: AutoModeRuntime,
  event: ContextEvent,
): ContextEventResult | void {
  if (!state.ownsControlFile) {
    const wasEnabled = state.enabled;
    refreshInheritedState();
    acceptControlRecord(latestChildControl(event.messages));
    applyInheritedTransition(runtime, wasEnabled);
  }

  const messages = event.messages.filter(
    (message) => !isManagedContextMessage(message),
  );
  let instruction: string | undefined;
  if (state.enabled) {
    state.pendingOffInstruction = false;
    instruction = AUTO_MODE_INSTRUCTIONS;
  } else if (state.pendingOffInstruction) {
    state.pendingOffInstruction = false;
    instruction = AUTO_MODE_OFF_INSTRUCTIONS;
  }

  if (!instruction && messages.length === event.messages.length) return;
  return {
    messages: instruction
      ? [
          ...messages,
          {
            role: "custom",
            customType: AUTO_MODE_INSTRUCTION_MESSAGE_TYPE,
            content: instruction,
            display: false,
            timestamp: Date.now(),
          },
        ]
      : messages,
  };
}

function appendChildControl(message: string, enabled: boolean): string {
  const marker = controlMarker(state.record);
  if (message.includes(marker)) return message;
  return `${message.trimEnd()}\n\n${childTransitionInstructions(enabled)}`;
}

function propagateAutoModeToSubagent(input: Record<string, unknown>): void {
  const action = typeof input.action === "string" ? input.action : undefined;
  const isLaunch =
    action === undefined &&
    (typeof input.agent === "string" || typeof input.workflowScript === "string");
  if (isLaunch) {
    if (state.enabled && typeof input.task === "string") {
      input.task = appendChildControl(input.task, true);
    }
    return;
  }

  if (action !== "steer" && action !== "resume") return;
  if (typeof input.message === "string") {
    input.message = appendChildControl(input.message, state.enabled);
  } else if (typeof input.task === "string") {
    input.task = appendChildControl(input.task, state.enabled);
  }
}

function handleToolCall(
  runtime: AutoModeRuntime,
  event: ToolCallEvent,
): ToolCallResult | void {
  syncInheritedRuntime(runtime);
  if (event.toolName === SUBAGENT_TOOL) {
    propagateAutoModeToSubagent(event.input);
    return;
  }
  if (!state.enabled || event.toolName !== ASK_USER_TOOL) return;

  return {
    block: true,
    reason:
      "Auto mode is active. Continue without asking the user; choose the safest reversible option and report the assumption.",
  };
}

function restoreOwnedControlEnvironment(): void {
  if (!state.ownsControlFile) return;
  if (state.previousControlEnvironment === undefined) {
    delete process.env[AUTO_MODE_CONTROL_ENV];
  } else {
    process.env[AUTO_MODE_CONTROL_ENV] = state.previousControlEnvironment;
  }
}

function removeOwnedControlFile(): void {
  if (!state.ownsControlFile) return;
  fs.rmSync(path.dirname(state.controlFile), { recursive: true, force: true });
}

function handleSessionShutdown(
  runtime: AutoModeRuntime,
  event: SessionShutdownEvent,
  context: ExtensionContext,
): void {
  if (event.reason === "reload") {
    restoreAskToolBaseline(runtime);
  } else {
    restoreAskToolAndForgetBaseline(runtime);
  }
  shutdownConfirmations(runtime);
  if (event.reason === "reload" || event.reason === "quit") {
    restoreOwnedControlEnvironment();
    removeOwnedControlFile();
  }
  context.ui.setStatus(AUTO_STATUS_KEY, undefined);
}

function updateStatus(ui: ExtensionUi): void {
  ui.setStatus(
    AUTO_STATUS_KEY,
    state.enabled ? ui.theme.fg("warning", "AUTO") : undefined,
  );
}

function resetAskToolBaseline(): void {
  state.askToolIndex = undefined;
}

function suppressAskTool(runtime: AutoModeRuntime): void {
  const activeTools = runtime.pi.getActiveTools();
  if (state.askToolIndex === undefined) {
    state.askToolIndex = activeTools.indexOf(ASK_USER_TOOL);
  }
  if (activeTools.includes(ASK_USER_TOOL)) {
    runtime.pi.setActiveTools(activeTools.filter((name) => name !== ASK_USER_TOOL));
  }
}

function restoreAskToolAndForgetBaseline(runtime: AutoModeRuntime): void {
  restoreAskToolBaseline(runtime);
  resetAskToolBaseline();
}

function restoreAskToolBaseline(runtime: AutoModeRuntime): void {
  const askToolIndex = state.askToolIndex;
  const activeTools = runtime.pi.getActiveTools();
  const askToolExists = runtime.pi
    .getAllTools()
    .some((tool) => tool.name === ASK_USER_TOOL);

  if (
    askToolIndex === undefined ||
    askToolIndex < 0 ||
    !askToolExists ||
    activeTools.includes(ASK_USER_TOOL)
  ) {
    return;
  }

  const restoredTools = [...activeTools];
  restoredTools.splice(
    Math.min(askToolIndex, restoredTools.length),
    0,
    ASK_USER_TOOL,
  );
  runtime.pi.setActiveTools(restoredTools);
}

function sendTransitionToActiveRun(
  runtime: AutoModeRuntime,
  context: ExtensionContext,
): void {
  if (context.isIdle()) return;

  runtime.pi.sendMessage(
    {
      customType: AUTO_MODE_TRANSITION_MESSAGE_TYPE,
      content: AUTO_MODE_TRANSITION_WAKE,
      display: false,
    },
    { triggerTurn: true, deliverAs: "steer" },
  );
}

function trackConfirmationStart(
  runtime: AutoModeRuntime,
  event: ToolExecutionStartEvent,
): void {
  if (event.toolName !== "subagent") return;

  const action = event.args?.action;
  const additional = event.args?.additional;
  if (
    action !== "grant-spawn-budget" ||
    additional === undefined ||
    !Number.isInteger(additional) ||
    additional <= 0
  ) {
    return;
  }

  runtime.pendingSpawnBudgetGrants.set(event.toolCallId, additional);
}

function installConfirmWrapper(runtime: AutoModeRuntime, ui: ExtensionUi): void {
  if (runtime.confirmBinding?.ui === ui && ui.confirm === runtime.confirmBinding.wrapped) {
    return;
  }

  restoreConfirmWrapper(runtime);
  const original = ui.confirm;
  const wrapped: ExtensionUi["confirm"] = (title, message, options) => {
    syncInheritedRuntime(runtime);
    if (!state.enabled) {
      return original.call(ui, title, message, options);
    }
    if (consumeExpectedSpawnBudgetPrompt(runtime, title, message)) {
      return Promise.resolve(true);
    }

    ui.notify(`Auto mode declined confirmation: ${title}`, "warning");
    return Promise.resolve(false);
  };

  ui.confirm = wrapped;
  runtime.confirmBinding = { ui, original, wrapped };
}

function isExpectedSpawnBudgetPrompt(message: string, additional: number): boolean {
  const sections = message.split("\n\n");
  if (
    sections.length !== 3 ||
    sections[0] !== `Add ${additional} launches to this logical session?` ||
    sections[2] !== SPAWN_BUDGET_SUFFIX
  ) {
    return false;
  }
  const budget =
    /^Spawn budget: (\d+)\/(\d+) used, (\d+) remaining \(configured (\d+); granted (\d+); grant allowance (\d+)\)$/.exec(
      sections[1] ?? "",
    );
  if (!budget) return false;
  const values = budget.slice(1).map(Number);
  if (values.length !== 6 || !values.every(Number.isSafeInteger)) return false;
  const [used, limit, remaining, configured, granted, grantAllowance] = values as [
    number,
    number,
    number,
    number,
    number,
    number,
  ];
  return [
    [limit, configured + granted],
    [remaining, Math.max(0, limit - used)],
    [grantAllowance, Math.max(0, configured - granted)],
  ].every(([actual, expected]) => actual === expected);
}

function consumeExpectedSpawnBudgetPrompt(
  runtime: AutoModeRuntime,
  title: string,
  message: string,
): boolean {
  if (title !== SPAWN_BUDGET_TITLE) return false;

  for (const [toolCallId, additional] of runtime.pendingSpawnBudgetGrants) {
    if (isExpectedSpawnBudgetPrompt(message, additional)) {
      runtime.pendingSpawnBudgetGrants.delete(toolCallId);
      return true;
    }
  }

  return false;
}

function shutdownConfirmations(runtime: AutoModeRuntime): void {
  runtime.pendingSpawnBudgetGrants.clear();
  restoreConfirmWrapper(runtime);
}

function restoreConfirmWrapper(runtime: AutoModeRuntime): void {
  if (!runtime.confirmBinding) return;
  if (runtime.confirmBinding.ui.confirm === runtime.confirmBinding.wrapped) {
    runtime.confirmBinding.ui.confirm = runtime.confirmBinding.original;
  }
  runtime.confirmBinding = undefined;
}
