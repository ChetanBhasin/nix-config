import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";

import {
  AfterCommandError,
  compactSettlementHistory,
  SESSION_RECORD_VERSION,
  SessionRegistry,
  advanceBarrier,
  barrierProgress,
  buildDependentPrompt,
  cancelBarrier,
  createBarrier,
  parseAfterCommand,
  type SessionBarrier,
  type SessionOutcome,
  type SessionSettlement,
  type SessionRecord,
} from "./coordinator.js";

const STATUS_KEY = "cb-session-coordinator";
const HEARTBEAT_INTERVAL_MS = 2_000;
const BARRIER_POLL_INTERVAL_MS = 500;
const MAX_USER_MESSAGE_CHARS = 4_000;
const MAX_ASSISTANT_MESSAGE_CHARS = 16_000;

const SUBMISSION_CONFIRMATION_TIMEOUT_MS = 60_000;
const MAX_EXPIRED_SUBMISSION_IDS = 32;
const SUBMISSION_MARKER_PATTERN = /<!-- pi-session-coordinator-submission:([0-9a-f-]{36}) -->/;

interface CoordinatorUi {
  notify(message: string, level?: "info" | "warning" | "error"): void;
  setStatus(key: string, value: string | undefined): void;
}

interface SessionManagerLike {
  getSessionId(): string;
  getSessionFile(): string | undefined;
  getBranch(): unknown[];
}

interface CoordinatorContext {
  cwd: string;
  mode: string;
  hasUI: boolean;
  ui: CoordinatorUi;
  sessionManager: SessionManagerLike;
  isIdle(): boolean;
}

interface CommandDefinition {
  description: string;
  handler(args: string, ctx: CoordinatorContext): Promise<void>;
}

type EventHandler = (event: unknown, ctx: CoordinatorContext) => unknown | Promise<unknown>;

export interface CoordinatorApi {
  on(eventName: string, handler: EventHandler): void;
  registerCommand(name: string, definition: CommandDefinition): void;
  getSessionName(): string | undefined;
  sendUserMessage(content: string, options?: { deliverAs: "steer" | "followUp" }): void;
}

export interface CoordinatorOptions {
  registryDirectory?: string;
  heartbeatIntervalMs?: number;
  pollIntervalMs?: number;
  submissionConfirmationTimeoutMs?: number;
  staleAfterMs?: number;
  now?: () => number;
}

interface MessageSummary {
  lastUserMessage?: string;
  lastAssistantMessage?: string;
  lastAssistantError?: string;
  outcome: SessionOutcome;
  resultTruncated: boolean;
}

interface SubmissionAttempt {
  id: string;
  barrierId: string;
  prompt: string;
  dependencyNames: string;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizedName(value: string | undefined): string | undefined {
  const name = value?.trim();
  return name ? name : undefined;
}

function contentText(content: unknown): string | undefined {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return undefined;

  const parts: string[] = [];
  for (const part of content) {
    if (!isObject(part)) continue;
    if (part.type === "text" && typeof part.text === "string") parts.push(part.text);
    if (part.type === "toolCall" && typeof part.name === "string") parts.push(`[tool call: ${part.name}]`);
  }
  const text = parts.join("\n").trim();
  return text.length > 0 ? text : undefined;
}

function truncateText(
  value: string | undefined,
  maximum: number,
  keep: "head" | "tail",
): { value?: string; truncated: boolean } {
  if (!value || value.length <= maximum) return { value, truncated: false };
  if (keep === "head") return { value: `${value.slice(0, maximum)}\n[…truncated…]`, truncated: true };
  return { value: `[…truncated…]\n${value.slice(-maximum)}`, truncated: true };
}

function summarizeSession(entries: unknown[]): MessageSummary {
  let lastUserMessage: string | undefined;
  let lastAssistantMessage: string | undefined;
  let lastAssistantError: string | undefined;
  let stopReason: string | undefined;

  for (const entry of entries) {
    if (!isObject(entry) || entry.type !== "message" || !isObject(entry.message)) continue;
    const message = entry.message;
    if (message.role === "user") lastUserMessage = contentText(message.content);
    if (message.role !== "assistant") continue;
    lastAssistantMessage = contentText(message.content);
    lastAssistantError = typeof message.errorMessage === "string" ? message.errorMessage : undefined;
    stopReason = typeof message.stopReason === "string" ? message.stopReason : undefined;
  }

  const user = truncateText(lastUserMessage, MAX_USER_MESSAGE_CHARS, "head");
  const assistant = truncateText(lastAssistantMessage, MAX_ASSISTANT_MESSAGE_CHARS, "tail");
  const error = truncateText(lastAssistantError, MAX_USER_MESSAGE_CHARS, "tail");
  let outcome: SessionOutcome = "unknown";
  if (stopReason === "error") outcome = "error";
  else if (stopReason === "aborted") outcome = "aborted";
  else if (stopReason === "stop") outcome = "completed";

  return {
    lastUserMessage: user.value,
    lastAssistantMessage: assistant.value,
    lastAssistantError: error.value,
    outcome,
    resultTruncated: user.truncated || assistant.truncated || error.truncated,
  };
}

function settlementFromSummary(
  revision: number,
  settledAt: number,
  summary: MessageSummary,
): SessionSettlement {
  return {
    revision,
    settledAt,
    outcome: summary.outcome,
    lastUserMessage: summary.lastUserMessage,
    lastAssistantMessage: summary.lastAssistantMessage,
    lastAssistantError: summary.lastAssistantError,
    resultTruncated: summary.resultTruncated || undefined,
  };
}

function registryDirectory(): string {
  const agentDirectory = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent");
  return process.env.PI_SESSION_COORDINATOR_DIR ?? join(agentDirectory, "session-coordinator", "v2", "instances");
}

function eventString(event: unknown, key: string): string | undefined {
  if (!isObject(event)) return undefined;
  const value = event[key];
  return typeof value === "string" ? value : undefined;
}

function submissionIdFromPrompt(prompt: string | undefined): string | undefined {
  return prompt?.match(SUBMISSION_MARKER_PATTERN)?.[1];
}

function formatRemaining(milliseconds: number): string {
  const seconds = Math.max(0, Math.ceil(milliseconds / 1000));
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.ceil(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  return `${Math.ceil(minutes / 60)}h`;
}

function usage(): string {
  return [
    "Usage:",
    "  /after A B -- <dependent prompt>",
    "  /after --timeout 30m \"Session A\" \"Session B\" -- <dependent prompt>",
    "  /after status",
    "  /after retry",
    "  /after cancel",
  ].join("\n");
}

export function registerSessionCoordinator(pi: CoordinatorApi, options: CoordinatorOptions = {}): void {
  const now = options.now ?? Date.now;
  const registry = new SessionRegistry(options.registryDirectory ?? registryDirectory());
  const heartbeatIntervalMs = options.heartbeatIntervalMs ?? HEARTBEAT_INTERVAL_MS;
  const pollIntervalMs = options.pollIntervalMs ?? BARRIER_POLL_INTERVAL_MS;
  const submissionConfirmationTimeoutMs =
    options.submissionConfirmationTimeoutMs ?? SUBMISSION_CONFIRMATION_TIMEOUT_MS;

  let context: CoordinatorContext | undefined;
  let record: SessionRecord | undefined;
  let sessionLive = false;
  let heartbeatTimer: NodeJS.Timeout | undefined;
  let barrierTimer: NodeJS.Timeout | undefined;
  let releaseTimer: NodeJS.Timeout | undefined;
  let submissionTimer: NodeJS.Timeout | undefined;
  let submissionAttempt: SubmissionAttempt | undefined;
  const expiredSubmissionIds = new Set<string>();
  let activeBarrier: SessionBarrier | undefined;
  let pollInFlight = false;
  let publishQueue: Promise<void> = Promise.resolve();
  let registryWarningShown = false;

  const isCurrentSession = (ctx: CoordinatorContext): boolean =>
    record?.sessionId === ctx.sessionManager.getSessionId();

  const reportRegistryError = (error: unknown): void => {
    const message = error instanceof Error ? error.message : String(error);
    if (!registryWarningShown && context?.hasUI) {
      context.ui.notify(`Session coordinator registry error: ${message}`, "error");
      registryWarningShown = true;
    }
    console.error(`[session-coordinator] ${message}`);
  };

  const publish = (): Promise<void> => {
    if (!record) return Promise.resolve();
    const snapshot = {
      ...record,
      settlements: record.settlements.map((settlement) => ({ ...settlement })),
    };
    publishQueue = publishQueue
      .then(() => registry.publish(snapshot))
      .then(() => {
        registryWarningShown = false;
      })
      .catch(reportRegistryError);
    return publishQueue;
  };

  const updateSummary = (ctx: CoordinatorContext): MessageSummary => {
    const summary: MessageSummary = record?.name
      ? summarizeSession(ctx.sessionManager.getBranch())
      : { outcome: "unknown", resultTruncated: false };
    if (!record) return summary;

    record.lastUserMessage = summary.lastUserMessage;
    record.lastAssistantMessage = summary.lastAssistantMessage;
    record.lastAssistantError = summary.lastAssistantError;
    record.outcome = summary.outcome;
    record.resultTruncated = summary.resultTruncated || undefined;
    if (!record.name) {
      record.settlements = record.settlements.map((settlement) => ({
        revision: settlement.revision,
        settledAt: settlement.settledAt,
        outcome: settlement.outcome,
        resultTruncated: settlement.resultTruncated,
      }));
    }
    return summary;
  };

  const updateBarrierStatus = (ctx: CoordinatorContext): void => {
    if (!activeBarrier) {
      ctx.ui.setStatus(STATUS_KEY, undefined);
      return;
    }
    if (activeBarrier.status === "submitting") {
      ctx.ui.setStatus(STATUS_KEY, "after: submitting (cancel)");
      return;
    }
    if (activeBarrier.status === "released") {
      let state = "ready (retry/cancel)";
      if (releaseTimer) state = ctx.isIdle() ? "submitting" : "ready (waiting for idle)";
      ctx.ui.setStatus(STATUS_KEY, `after: ${state}`);
      return;
    }
    const progress = barrierProgress(activeBarrier);
    const waiting = [...progress.unresolved, ...progress.running];
    const remaining = formatRemaining(activeBarrier.deadlineAt - now());
    ctx.ui.setStatus(STATUS_KEY, `after: ${waiting.join(", ")} (${remaining})`);
  };

  const beginActivity = async (ctx: CoordinatorContext): Promise<void> => {
    if (!record || !sessionLive || record.phase === "running") return;
    record.activityRevision += 1;
    record.phase = "running";
    record.updatedAt = now();
    record.heartbeatAt = record.updatedAt;
    await publish();
    updateBarrierStatus(ctx);
  };

  const publishSettledRevision = async (ctx: CoordinatorContext, timestamp: number): Promise<void> => {
    if (!record) return;
    const summary = updateSummary(ctx);
    record.phase = "settled";
    record.settledRevision = record.activityRevision;
    record.settledAt = timestamp;
    record.settlements = compactSettlementHistory([
      ...record.settlements,
      settlementFromSummary(record.settledRevision, timestamp, summary),
    ]);
    record.updatedAt = timestamp;
    record.heartbeatAt = timestamp;
    await publish();
    updateBarrierStatus(ctx);
  };

  const settleActivity = async (ctx: CoordinatorContext): Promise<void> => {
    if (!record || !sessionLive || record.phase !== "running") return;
    await publishSettledRevision(ctx, now());
  };

  const settleTreeNavigation = async (ctx: CoordinatorContext): Promise<void> => {
    if (!record || !sessionLive || record.phase === "running") return;
    record.activityRevision += 1;
    await publishSettledRevision(ctx, now());
  };

  const stopBarrierTimer = (): void => {
    if (barrierTimer) clearInterval(barrierTimer);
    barrierTimer = undefined;
  };

  const clearSubmissionTracking = (expire: boolean): void => {
    if (submissionTimer) clearTimeout(submissionTimer);
    submissionTimer = undefined;
    if (expire && submissionAttempt) {
      expiredSubmissionIds.add(submissionAttempt.id);
      if (expiredSubmissionIds.size > MAX_EXPIRED_SUBMISSION_IDS) {
        const oldest = expiredSubmissionIds.values().next().value;
        if (oldest) expiredSubmissionIds.delete(oldest);
      }
    }
    submissionAttempt = undefined;
  };

  const clearBarrier = (ctx: CoordinatorContext, expireSubmission = true): void => {
    if (releaseTimer) clearTimeout(releaseTimer);
    releaseTimer = undefined;
    clearSubmissionTracking(expireSubmission);
    activeBarrier = undefined;
    stopBarrierTimer();
    updateBarrierStatus(ctx);
  };

  const dispatchReleasedPrompt = (ctx: CoordinatorContext): void => {
    const barrier = activeBarrier;
    if (!barrier || barrier.status !== "released" || releaseTimer || submissionAttempt) return;

    if (!ctx.isIdle()) {
      releaseTimer = setTimeout(() => {
        releaseTimer = undefined;
        if (!sessionLive || !isCurrentSession(ctx)) return;
        dispatchReleasedPrompt(ctx);
      }, pollIntervalMs);
      releaseTimer.unref();
      updateBarrierStatus(ctx);
      return;
    }

    let dependentPrompt: string;
    try {
      dependentPrompt = buildDependentPrompt(barrier);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      ctx.ui.notify(`Could not prepare the dependent prompt: ${message}. Use /after retry or /after cancel.`, "error");
      updateBarrierStatus(ctx);
      return;
    }

    const barrierId = barrier.id;
    releaseTimer = setTimeout(() => {
      releaseTimer = undefined;
      if (!sessionLive || !isCurrentSession(ctx)) return;
      if (!activeBarrier || activeBarrier.id !== barrierId || activeBarrier.status !== "released") return;
      if (!ctx.isIdle()) {
        dispatchReleasedPrompt(ctx);
        return;
      }

      const attemptId = randomUUID();
      const dependencyNames = activeBarrier.dependencies.map((dependency) => dependency.name).join(", ");
      const prompt = `<!-- pi-session-coordinator-submission:${attemptId} -->\n${dependentPrompt}`;
      const attempt: SubmissionAttempt = { id: attemptId, barrierId, prompt, dependencyNames };
      submissionAttempt = attempt;
      activeBarrier = { ...activeBarrier, status: "submitting" };
      updateBarrierStatus(ctx);

      try {
        pi.sendUserMessage(prompt);
      } catch (error) {
        clearSubmissionTracking(false);
        if (activeBarrier?.id === barrierId) activeBarrier = { ...activeBarrier, status: "released" };
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(`Could not submit the dependent prompt: ${message}. Use /after retry or /after cancel.`, "error");
        updateBarrierStatus(ctx);
        return;
      }

      if (submissionAttempt !== attempt) return;
      submissionTimer = setTimeout(() => {
        if (submissionAttempt !== attempt || activeBarrier?.id !== barrierId) return;
        clearSubmissionTracking(true);
        activeBarrier = { ...activeBarrier, status: "released" };
        ctx.ui.notify(
          `Dependent prompt submission was not confirmed within ${formatRemaining(submissionConfirmationTimeoutMs)}; ` +
            "the prompt is retained. Use /after retry or /after cancel.",
          "error",
        );
        updateBarrierStatus(ctx);
      }, submissionConfirmationTimeoutMs);
      submissionTimer.unref();
    }, 0);
    releaseTimer.unref();
    updateBarrierStatus(ctx);
  };

  const confirmSubmission = (event: unknown, ctx: CoordinatorContext): void => {
    const attempt = submissionAttempt;
    if (!attempt || activeBarrier?.id !== attempt.barrierId || activeBarrier.status !== "submitting") return;
    if (submissionIdFromPrompt(eventString(event, "prompt")) !== attempt.id) return;

    const dependencyNames = attempt.dependencyNames;
    clearBarrier(ctx, false);
    ctx.ui.notify(`Submitted the dependent prompt after: ${dependencyNames}`, "info");
  };

  const pollBarrier = async (ctx: CoordinatorContext): Promise<void> => {
    if (!activeBarrier || pollInFlight || !sessionLive) return;
    if (activeBarrier.status === "released") {
      dispatchReleasedPrompt(ctx);
      return;
    }
    if (activeBarrier.status !== "pending") return;
    const barrierId = activeBarrier.id;
    pollInFlight = true;
    try {
      const records = await registry.readAll();
      if (!activeBarrier || activeBarrier.id !== barrierId || !sessionLive) return;
      const next = advanceBarrier(activeBarrier, records, {
        now: now(),
        staleAfterMs: options.staleAfterMs,
      });
      activeBarrier = next;
      if (next.status === "pending") {
        updateBarrierStatus(ctx);
        return;
      }

      if (next.status === "released") {
        stopBarrierTimer();
        updateBarrierStatus(ctx);
        const names = next.dependencies.map((dependency) => dependency.name).join(", ");
        ctx.ui.notify(`Sessions settled: ${names}. Submitting the dependent prompt.`, "info");
        dispatchReleasedPrompt(ctx);
      } else {
        clearBarrier(ctx);
        ctx.ui.notify(`Session dependency failed: ${next.failure ?? next.status}`, "error");
      }
    } catch (error) {
      reportRegistryError(error);
    } finally {
      pollInFlight = false;
    }
  };

  const startBarrierTimer = (ctx: CoordinatorContext): void => {
    stopBarrierTimer();
    barrierTimer = setInterval(() => {
      void pollBarrier(ctx);
    }, pollIntervalMs);
    barrierTimer.unref();
  };

  const cancelPendingBarrier = (ctx: CoordinatorContext, notify: boolean): void => {
    if (releaseTimer) {
      clearTimeout(releaseTimer);
      releaseTimer = undefined;
    }
    if (!activeBarrier) {
      if (notify) ctx.ui.notify("No session dependency is pending", "warning");
      return;
    }
    const cancelled =
      activeBarrier.status === "pending"
        ? cancelBarrier(activeBarrier, now())
        : { ...activeBarrier, status: "cancelled" as const, completedAt: now() };
    clearBarrier(ctx);
    if (notify) {
      const names = cancelled.dependencies.map((dependency) => dependency.name).join(", ");
      ctx.ui.notify(`Cancelled session dependency: ${names}`, "info");
    }
  };

  pi.registerCommand("after", {
    description: "Run a prompt after named independent Pi sessions settle",
    handler: async (args, ctx) => {
      let command;
      try {
        command = parseAfterCommand(args);
      } catch (error) {
        const message = error instanceof AfterCommandError ? error.message : String(error);
        ctx.ui.notify(`${message}\n${usage()}`, "warning");
        return;
      }

      if (command.kind === "help") {
        ctx.ui.notify(usage(), "info");
        return;
      }
      if (command.kind === "cancel") {
        cancelPendingBarrier(ctx, true);
        return;
      }
      if (command.kind === "retry") {
        if (!activeBarrier || activeBarrier.status !== "released") {
          ctx.ui.notify("No released dependent prompt is ready to retry", "warning");
          return;
        }
        dispatchReleasedPrompt(ctx);
        return;
      }
      if (command.kind === "status") {
        if (!activeBarrier) {
          ctx.ui.notify("No session dependency is pending", "info");
          return;
        }
        if (activeBarrier.status === "submitting") {
          ctx.ui.notify("The dependent prompt is awaiting submission confirmation; use /after cancel to stop waiting", "info");
          return;
        }
        if (activeBarrier.status === "released") {
          let state = "is ready; use /after retry or /after cancel";
          if (releaseTimer) {
            state = ctx.isIdle() ? "is being submitted" : "is ready and waiting for this session to become idle";
          }
          ctx.ui.notify(`The dependent prompt ${state}`, "info");
          return;
        }
        await pollBarrier(ctx);
        if (!activeBarrier) return;
        const progress = barrierProgress(activeBarrier);
        const details = [
          progress.settled.length > 0 ? `settled: ${progress.settled.join(", ")}` : undefined,
          progress.running.length > 0 ? `running: ${progress.running.join(", ")}` : undefined,
          progress.unresolved.length > 0 ? `not registered: ${progress.unresolved.join(", ")}` : undefined,
          `timeout: ${formatRemaining(activeBarrier.deadlineAt - now())}`,
        ].filter((line): line is string => line !== undefined);
        ctx.ui.notify(details.join("\n"), "info");
        return;
      }

      if (ctx.mode !== "tui" && ctx.mode !== "rpc") {
        ctx.ui.notify("/after requires a long-lived TUI or RPC session; print and JSON modes exit too early", "error");
        return;
      }

      if (!sessionLive || !record || !isCurrentSession(ctx)) {
        ctx.ui.notify("The session coordinator is not ready for this session", "error");
        return;
      }
      if (!ctx.isIdle()) {
        ctx.ui.notify("Schedule /after when this dependent session is idle", "warning");
        return;
      }
      if (activeBarrier || releaseTimer) {
        ctx.ui.notify("A dependent prompt is already queued; use /after status or /after cancel", "warning");
        return;
      }

      activeBarrier = createBarrier(command, record.ownerId, now());
      updateBarrierStatus(ctx);
      startBarrierTimer(ctx);
      await pollBarrier(ctx);
      if (activeBarrier?.status === "pending") ctx.ui.notify(`Waiting for: ${command.names.join(", ")}`, "info");
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    context = ctx;
    sessionLive = true;
    const timestamp = now();
    const name = normalizedName(pi.getSessionName());
    record = {
      version: SESSION_RECORD_VERSION,
      ownerId: randomUUID(),
      pid: process.pid,
      processStartedAt: timestamp,
      sessionId: ctx.sessionManager.getSessionId(),
      sessionFile: ctx.sessionManager.getSessionFile(),
      cwd: ctx.cwd,
      name,
      nameRegisteredAt: name ? timestamp : undefined,
      nameRegisteredRevision: name ? 0 : undefined,
      mode: ctx.mode,
      phase: "settled",
      activityRevision: 0,
      settledRevision: 0,
      settlements: [],
      updatedAt: timestamp,
      heartbeatAt: timestamp,
      settledAt: timestamp,
      outcome: "unknown",
    };
    const initialSummary = updateSummary(ctx);
    record.settlements = [settlementFromSummary(0, timestamp, initialSummary)];
    await publish();
    try {
      await registry.cleanup(timestamp);
    } catch (error) {
      reportRegistryError(error);
    }

    heartbeatTimer = setInterval(() => {
      if (!record || !sessionLive) return;
      record.heartbeatAt = now();
      void publish();
    }, heartbeatIntervalMs);
    heartbeatTimer.unref();
  });

  pi.on("session_info_changed", async (_event, ctx) => {
    if (!record || !sessionLive) return;
    const timestamp = now();
    const name = normalizedName(pi.getSessionName());
    if (name !== record.name) {
      record.nameRegisteredAt = name ? timestamp : undefined;
      record.nameRegisteredRevision = name ? record.activityRevision : undefined;
    }
    record.name = name;
    const summary = updateSummary(ctx);
    if (record.phase === "settled" && record.settledAt !== undefined) {
      const settledRevision = record.settledRevision;
      const replacement = settlementFromSummary(settledRevision, record.settledAt, summary);
      record.settlements = record.settlements.map((settlement) =>
        settlement.revision === settledRevision ? replacement : settlement,
      );
    }
    record.updatedAt = timestamp;
    record.heartbeatAt = record.updatedAt;
    await publish();
    updateBarrierStatus(ctx);
  });

  pi.on("input", (event, ctx) => {
    if (eventString(event, "source") !== "extension") return;
    const submissionId = submissionIdFromPrompt(eventString(event, "text"));
    if (!submissionId || !expiredSubmissionIds.delete(submissionId)) return;
    ctx.ui.notify("Discarded a superseded dependent-prompt submission attempt", "warning");
    return { action: "handled" };
  });

  pi.on("before_agent_start", async (event, ctx) => {
    confirmSubmission(event, ctx);
    await beginActivity(ctx);
  });
  pi.on("agent_start", async (_event, ctx) => beginActivity(ctx));
  pi.on("agent_settled", async (_event, ctx) => settleActivity(ctx));
  pi.on("session_tree", async (_event, ctx) => settleTreeNavigation(ctx));

  pi.on("session_shutdown", async (event, ctx) => {
    const reason = eventString(event, "reason") ?? "unknown";
    const discardedPendingPrompt = Boolean(activeBarrier || releaseTimer);
    sessionLive = false;
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    heartbeatTimer = undefined;
    if (discardedPendingPrompt && reason !== "quit" && ctx.hasUI) {
      ctx.ui.notify(`Cancelled the queued /after prompt during session ${reason}`, "warning");
    }
    cancelPendingBarrier(ctx, false);
    context = undefined;

    if (!record) return;
    const timestamp = now();
    record.phase = "closed";
    record.closedAt = timestamp;
    record.closedReason = reason;
    record.updatedAt = timestamp;
    record.heartbeatAt = timestamp;
    await publish();
  });
}

export default function sessionCoordinatorExtension(pi: CoordinatorApi): void {
  registerSessionCoordinator(pi);
}
