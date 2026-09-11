import type { ExtensionAPI, ExtensionCommandContext } from "../../npm/node_modules/@earendil-works/pi-coding-agent/dist/index.js";
import { WorkflowLedger, type Retirement } from "./workflow-ledger.js";
import { digest } from "./workflow-workspace.js";

/** Human-only decisions: deliberately absent from workflow_contract's tool schema. */
export function registerHumanWorkflow(pi: ExtensionAPI, ledger: WorkflowLedger, options: {
  owner: () => boolean;
  drained: () => void;
  report: (ctx: ExtensionCommandContext) => string;
}): void {
  pi.registerCommand("workflow", {
    description: "Workflow status/history; confirmed cancel, archive, reset, remove <ids> -- <reason>, request <text>",
    async handler(args, ctx) {
      const [action = "status", ...parts] = args.trim().split(/\s+/).filter(Boolean);
      if (action === "status" || action === "history") {
        ctx.ui.notify(action === "history" ? JSON.stringify(ledger.audit) : options.report(ctx), "info");
        return;
      }
      if (!["cancel", "archive", "reset", "remove", "request"].includes(action)) {
        ctx.ui.notify("Usage: /workflow status|history|cancel|archive|reset [reason]; remove <ids> -- <reason>; request <text>", "warning");
        return;
      }
      // RPC is a transport, not human authority. Never accept a tool's boolean confirmation.
      if (!options.owner() || ctx.mode !== "tui" || !ctx.hasUI) throw new Error("Human workflow changes require the owner TUI and explicit confirmation");
      if (!ctx.isIdle() || ctx.hasPendingMessages()) throw new Error("Stop/wait for the current run and queued messages before changing workflow scope");
      options.drained();
      const separator = parts.indexOf("--");
      const ids = action === "remove" ? (separator < 0 ? parts : parts.slice(0, separator)) : [];
      if (action === "remove") ledger.removal(ids); // Validate before prompting; preserve at least one mandatory criterion.
      if (["cancel", "archive"].includes(action)) ledger.require();
      const reason = action === "remove" ? parts.slice(separator < 0 ? parts.length : separator + 1).join(" ") : parts.join(" ");
      const before = () => digest([ctx.sessionManager.getSessionId(), ledger.contract, ledger.input, ledger.fault]);
      const snapshot = before();
      const explanation = reason || await ctx.ui.input("Reason for workflow change?");
      if (!explanation?.trim()) return;
      const affected = ledger.contract?.requirements.filter((r) => !ids.length || ids.includes(r.id))
        .map((r) => `${r.id}${r.mandatory ? " [mandatory]" : ""}: ${r.expected}`).join("\n") ?? "No active requirements";
      const confirmed = await ctx.ui.confirm(`Workflow ${action}?`, `${explanation}\n\n${affected}\n\nNo successful completion is invented. History and writer leases are retained. A reset needs a new request before starting work.`);
      if (!ctx.isIdle() || ctx.hasPendingMessages() || snapshot !== before()) throw new Error("Workflow changed during confirmation; nothing changed, retry against current status");
      options.drained();
      if (!confirmed) {
        ledger.logHuman(action, explanation, false);
        ctx.ui.notify("Workflow unchanged", "info");
        return;
      }
      if (action === "remove") ledger.removeRequirements(ids, explanation);
      else if (action === "request") {
        ledger.logHuman(action, explanation, true);
        ledger.receiveInput("interactive", explanation, ctx.sessionManager.getLeafId(), true);
      } else ledger.retire(action as Retirement["action"], explanation);
      ctx.ui.notify(options.report(ctx), "info");
    },
  });
}
