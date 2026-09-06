import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  MAX_BARRIER_TIMEOUT_MS,
  SessionRegistry,
  advanceBarrier,
  createBarrier,
} from "./coordinator.ts";
import { registerSessionCoordinator } from "./index.ts";

function harness(directory) {
  const handlers = new Map();
  const commands = new Map();
  const sent = [];
  const notifications = [];
  const statuses = new Map();
  let name = "dependent";
  let clock = 1_700_000_000_000;
  let idle = true;
  let branch = [];
  let sendFailure;
  let autoConfirmSubmission = true;

  const context = {
    cwd: "/tmp/dependent-project",
    mode: "tui",
    hasUI: true,
    ui: {
      notify(message, level) {
        notifications.push({ message, level });
      },
      setStatus(key, value) {
        if (value === undefined) statuses.delete(key);
        else statuses.set(key, value);
      },
    },
    sessionManager: {
      getSessionId: () => "dependent-session",
      getSessionFile: () => "/tmp/dependent-session.jsonl",
      getBranch: () => branch,
    },
    isIdle: () => idle,
  };

  const emitHandlers = async (eventName, event = {}) => {
    const results = [];
    for (const handler of handlers.get(eventName) ?? []) results.push(await handler(event, context));
    return results;
  };

  const api = {
    on(eventName, handler) {
      const existing = handlers.get(eventName) ?? [];
      existing.push(handler);
      handlers.set(eventName, existing);
    },
    registerCommand(commandName, definition) {
      commands.set(commandName, definition);
    },
    getSessionName: () => name,
    sendUserMessage(content, options) {
      if (sendFailure) throw sendFailure;
      sent.push({ content, options });
      if (!autoConfirmSubmission) return;
      queueMicrotask(() => {
        void emitHandlers("input", { text: content, source: "extension" }).then((results) => {
          if (results.some((result) => result?.action === "handled")) return;
          return emitHandlers("before_agent_start", { prompt: content });
        });
      });
    },
  };

  registerSessionCoordinator(api, {
    registryDirectory: directory,
    heartbeatIntervalMs: 60_000,
    pollIntervalMs: 5,
    submissionConfirmationTimeoutMs: 20,
    staleAfterMs: 100,
    now: () => clock,
  });

  return {
    context,
    sent,
    notifications,
    statuses,
    command: (args) => commands.get("after").handler(args, context),
    emit: emitHandlers,
    setClock(value) {
      clock = value;
    },
    setIdle(value) {
      idle = value;
    },
    setMode(value) {
      context.mode = value;
    },
    setSendFailure(value) {
      sendFailure = value;
    },
    setAutoConfirmSubmission(value) {
      autoConfirmSubmission = value;
    },
    setName(value) {
      name = value;
    },
    setBranch(value) {
      branch = value;
    },
  };
}

function targetRecord(overrides = {}) {
  const now = 1_700_000_000_000;
  const record = {
    version: 2,
    ownerId: "target-owner",
    pid: process.pid,
    processStartedAt: now - 1_000,
    sessionId: "target-session",
    sessionFile: "/tmp/target-session.jsonl",
    cwd: "/tmp/target-project",
    name: "A",
    nameRegisteredAt: now - 1_000,
    nameRegisteredRevision: 0,
    mode: "interactive",
    phase: "running",
    activityRevision: 1,
    settledRevision: 0,
    updatedAt: now,
    heartbeatAt: now,
    settledAt: now - 100,
    outcome: "unknown",
    ...overrides,
  };
  if (!("settlements" in overrides)) {
    record.settlements = [
      {
        revision: record.settledRevision,
        settledAt: record.settledAt,
        outcome: record.outcome ?? "unknown",
        lastUserMessage: record.lastUserMessage,
        lastAssistantMessage: record.lastAssistantMessage,
        lastAssistantError: record.lastAssistantError,
        resultTruncated: record.resultTruncated,
      },
    ];
  }
  return record;
}

const cleanupDirectories = [];

afterEach(async () => {
  while (cleanupDirectories.length > 0) {
    await rm(cleanupDirectories.pop(), { recursive: true, force: true });
  }
});

async function setup() {
  const directory = await mkdtemp(join(tmpdir(), "pi-session-coordinator-index-"));
  cleanupDirectories.push(directory);
  const instance = harness(directory);
  await instance.emit("session_start");
  return { directory, instance, registry: new SessionRegistry(directory) };
}

describe("session coordinator extension", () => {
  test("rejects new barriers in one-shot print mode", async () => {
    const { instance } = await setup();
    instance.setMode("print");

    await instance.command("A -- Do not queue this");

    expect(instance.sent).toHaveLength(0);
    expect(instance.notifications.at(-1).message).toContain("requires a long-lived TUI or RPC session");
  });

  test("publishes one revision per agent cycle and tracks rename/settle metadata", async () => {
    const { instance, registry } = await setup();

    let own = (await registry.readAll()).find((record) => record.sessionId === "dependent-session");
    expect(own.phase).toBe("settled");
    expect(own.activityRevision).toBe(0);

    await instance.emit("before_agent_start");
    await instance.emit("agent_start");
    own = (await registry.readAll()).find((record) => record.sessionId === "dependent-session");
    expect(own.phase).toBe("running");
    expect(own.activityRevision).toBe(1);

    instance.setBranch([
      { type: "message", message: { role: "user", content: "Do the work" } },
      { type: "message", message: { role: "assistant", content: [{ type: "text", text: "Done" }], stopReason: "stop" } },
    ]);
    await instance.emit("agent_settled");
    instance.setName("renamed target");
    instance.setClock(1_700_000_000_010);
    await instance.emit("session_info_changed");

    own = (await registry.readAll()).find((record) => record.sessionId === "dependent-session");
    expect(own.phase).toBe("settled");
    expect(own.settledRevision).toBe(1);
    expect(own.lastAssistantMessage).toBe("Done");
    expect(own.outcome).toBe("completed");
    expect(own.name).toBe("renamed target");
    expect(own.nameRegisteredAt).toBe(1_700_000_000_010);
    expect(own.nameRegisteredRevision).toBe(1);
    expect(own.settlements.map((settlement) => settlement.revision)).toEqual([0, 1]);
    expect(own.settlements[1].lastAssistantMessage).toBe("Done");

    await instance.emit("session_shutdown", { reason: "quit" });
  });

  test("retains on-time revision evidence past the maximum timeout for delayed polling", async () => {
    const start = 1_700_000_000_000;
    const deadline = start + MAX_BARRIER_TIMEOUT_MS;
    const directory = await mkdtemp(join(tmpdir(), "pi-session-coordinator-index-"));
    cleanupDirectories.push(directory);
    const producer = harness(directory);
    producer.setName("A");
    await producer.emit("session_start");
    await producer.emit("before_agent_start");

    const registry = new SessionRegistry(directory);
    await registry.publish(
      targetRecord({
        ownerId: "target-b-owner",
        sessionId: "target-b-session",
        sessionFile: "/tmp/target-b-session.jsonl",
        name: "B",
      }),
    );

    const waiting = createBarrier(
      {
        kind: "schedule",
        names: ["A", "B"],
        prompt: "Combine both on-time results",
        timeoutMs: MAX_BARRIER_TIMEOUT_MS,
      },
      "waiting-owner",
      start,
      "maximum-timeout-barrier",
    );
    const bound = advanceBarrier(waiting, await registry.readAll(), {
      now: start,
      isProcessAlive: () => true,
    });
    expect(bound.status).toBe("pending");
    expect(bound.dependencies.map((dependency) => dependency.requiredRevision)).toEqual([1, 1]);

    producer.setClock(start + 100);
    producer.setBranch([
      { type: "message", message: { role: "user", content: "First task" } },
      { type: "message", message: { role: "assistant", content: "A on time", stopReason: "stop" } },
    ]);
    await producer.emit("agent_settled");

    producer.setClock(deadline + 101);
    await producer.emit("before_agent_start");
    producer.setBranch([
      { type: "message", message: { role: "user", content: "Unrelated later task" } },
      { type: "message", message: { role: "assistant", content: "A later result", stopReason: "stop" } },
    ]);
    await producer.emit("agent_settled");

    await registry.publish(
      targetRecord({
        ownerId: "target-b-owner",
        sessionId: "target-b-session",
        sessionFile: "/tmp/target-b-session.jsonl",
        name: "B",
        phase: "settled",
        settledRevision: 1,
        settledAt: deadline,
        updatedAt: deadline,
        heartbeatAt: deadline,
        outcome: "completed",
        lastAssistantMessage: "B on time",
      }),
    );

    const records = await registry.readAll();
    const producerRecord = records.find((candidate) => candidate.name === "A");
    expect(producerRecord.settlements.map((settlement) => settlement.revision)).toContain(1);

    const released = advanceBarrier(bound, records, {
      now: deadline + 101,
      isProcessAlive: () => true,
    });
    expect(released.status).toBe("released");
    expect(released.dependencies[0].snapshot.settledRevision).toBe(1);
    expect(released.dependencies[0].snapshot.lastAssistantMessage).toBe("A on time");
    expect(released.dependencies[1].snapshot.settledAt).toBe(deadline);

    await producer.emit("session_shutdown", { reason: "quit" });
  });

  test("publishes tree navigation as a new settled revision", async () => {
    const { instance, registry } = await setup();
    instance.setBranch([
      { type: "message", message: { role: "user", content: "Earlier task" } },
      { type: "message", message: { role: "assistant", content: "Earlier result", stopReason: "stop" } },
    ]);
    instance.setClock(1_700_000_000_020);

    await instance.emit("session_tree");

    const own = (await registry.readAll()).find((record) => record.sessionId === "dependent-session");
    expect(own.phase).toBe("settled");
    expect(own.activityRevision).toBe(1);
    expect(own.settledRevision).toBe(1);
    expect(own.settlements.map((settlement) => settlement.revision)).toEqual([0, 1]);
    expect(own.settlements[1].lastAssistantMessage).toBe("Earlier result");
    await instance.emit("session_shutdown", { reason: "quit" });
  });

  test("does not report length-limited assistant output as completed", async () => {
    const { instance, registry } = await setup();
    await instance.emit("before_agent_start", { prompt: "Generate a report" });
    instance.setBranch([
      { type: "message", message: { role: "user", content: "Generate a report" } },
      { type: "message", message: { role: "assistant", content: "Partial report", stopReason: "length" } },
    ]);

    await instance.emit("agent_settled");

    const own = (await registry.readAll()).find((record) => record.sessionId === "dependent-session");
    expect(own.outcome).toBe("unknown");
    expect(own.settlements[1].outcome).toBe("unknown");
    await instance.emit("session_shutdown", { reason: "quit" });
  });

  test("publishes conversation text only after the session is explicitly named", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pi-session-coordinator-index-"));
    cleanupDirectories.push(directory);
    const instance = harness(directory);
    instance.setName(undefined);
    instance.setBranch([
      { type: "message", message: { role: "user", content: "private prompt" } },
      { type: "message", message: { role: "assistant", content: "private result", stopReason: "stop" } },
    ]);
    await instance.emit("session_start");
    const registry = new SessionRegistry(directory);

    let own = (await registry.readAll()).find((record) => record.sessionId === "dependent-session");
    expect(own.lastUserMessage).toBeUndefined();
    expect(own.lastAssistantMessage).toBeUndefined();

    expect(own.settlements[0].lastUserMessage).toBeUndefined();
    expect(own.settlements[0].lastAssistantMessage).toBeUndefined();
    instance.setName("shared");
    await instance.emit("session_info_changed");
    own = (await registry.readAll()).find((record) => record.sessionId === "dependent-session");
    expect(own.lastUserMessage).toBe("private prompt");
    expect(own.lastAssistantMessage).toBe("private result");

    instance.setName(undefined);
    await instance.emit("session_info_changed");
    own = (await registry.readAll()).find((record) => record.sessionId === "dependent-session");
    expect(own.lastUserMessage).toBeUndefined();
    expect(own.settlements[0].lastUserMessage).toBeUndefined();
    await instance.emit("session_shutdown", { reason: "quit" });
  });

  test("submits the queued prompt exactly once when the target settles", async () => {
    const { instance, registry } = await setup();
    await registry.publish(targetRecord());

    await instance.command("A -- Combine the target result");
    expect(instance.sent).toHaveLength(0);

    await registry.publish(
      targetRecord({
        phase: "settled",
        settledRevision: 1,
        settledAt: 1_700_000_000_100,
        outcome: "completed",
        lastAssistantMessage: "Target result",
      }),
    );
    instance.setClock(1_700_000_000_100);
    await instance.command("status");
    await Bun.sleep(10);
    await instance.command("status");

    expect(instance.sent).toHaveLength(1);
    expect(instance.sent[0].content).toContain("Target result");
    expect(instance.sent[0].content).toContain("Combine the target result");
    await instance.emit("session_shutdown", { reason: "quit" });
  });

  test("waits for the dependent session to become idle before submitting", async () => {
    const { instance, registry } = await setup();
    await registry.publish(targetRecord());
    await instance.command("A -- Run after my current turn");

    instance.setIdle(false);
    await registry.publish(targetRecord({ phase: "settled", settledRevision: 1 }));
    await instance.command("status");
    await Bun.sleep(10);

    expect(instance.sent).toHaveLength(0);
    expect([...instance.statuses.values()][0]).toContain("waiting for idle");

    instance.setIdle(true);
    await Bun.sleep(10);
    expect(instance.sent).toHaveLength(1);
    expect(instance.sent[0].options).toBeUndefined();
    await instance.emit("session_shutdown", { reason: "quit" });
  });

  test("retains a released prompt for explicit retry after submission fails", async () => {
    const { instance, registry } = await setup();
    await registry.publish(targetRecord());
    await instance.command("A -- Retry this handoff");
    instance.setSendFailure(new Error("synthetic send failure"));
    await registry.publish(targetRecord({ phase: "settled", settledRevision: 1 }));

    await instance.command("status");
    await Bun.sleep(10);
    expect(instance.sent).toHaveLength(0);
    expect([...instance.statuses.values()][0]).toContain("ready");
    expect(instance.notifications.some(({ message }) => message.includes("/after retry"))).toBe(true);

    instance.setSendFailure(undefined);
    await instance.command("retry");
    await Bun.sleep(10);
    expect(instance.sent).toHaveLength(1);
    expect([...instance.statuses.values()]).toHaveLength(0);
    await instance.emit("session_shutdown", { reason: "quit" });
  });

  test("retains a prompt when asynchronous submission is not confirmed", async () => {
    const { instance, registry } = await setup();
    await registry.publish(targetRecord());
    await instance.command("A -- Retry an unconfirmed handoff");
    instance.setAutoConfirmSubmission(false);
    await registry.publish(targetRecord({ phase: "settled", settledRevision: 1 }));

    await instance.command("status");
    await Bun.sleep(30);

    expect(instance.sent).toHaveLength(1);
    expect([...instance.statuses.values()][0]).toContain("ready");
    expect(instance.notifications.some(({ message }) => message.includes("was not confirmed"))).toBe(true);

    const staleResults = await instance.emit("input", {
      text: instance.sent[0].content,
      source: "extension",
    });
    expect(staleResults.some((result) => result?.action === "handled")).toBe(true);

    instance.setAutoConfirmSubmission(true);
    await instance.command("retry");
    await Bun.sleep(10);
    expect(instance.sent).toHaveLength(2);
    expect(instance.sent[1].content).not.toBe(instance.sent[0].content);
    expect([...instance.statuses.values()]).toHaveLength(0);
    await instance.emit("session_shutdown", { reason: "quit" });
  });

  test("cancellation prevents a later target settlement from submitting", async () => {
    const { instance, registry } = await setup();
    await registry.publish(targetRecord());

    await instance.command("A -- This must not run");
    await instance.command("cancel");
    await registry.publish(targetRecord({ phase: "settled", settledRevision: 1 }));
    await Bun.sleep(15);

    expect(instance.sent).toHaveLength(0);
    expect([...instance.statuses.values()]).toHaveLength(0);
    await instance.emit("session_shutdown", { reason: "quit" });
  });
});
