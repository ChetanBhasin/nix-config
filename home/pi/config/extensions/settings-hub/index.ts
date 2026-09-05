// Pi provides this module to extensions through its host module loader.
import {
  CustomEditor,
  DefaultPackageManager,
  SettingsManager,
  getAgentDir,
} from "@earendil-works/pi-coding-agent";
import { installSettingsInterceptor, type SettingsInterceptorState } from "./interceptor.js";
import { openSettingsHub, type HubServices } from "./settings-hub.js";
import type { PackageManagerLike, SettingsManagerLike } from "./resources.js";
import type { CommandContext, HubAction, HubContext, PiApi, SubmitHandler } from "./types.js";

interface SettingsManagerRuntime {
  create(cwd: string, agentDir: string): SettingsManagerLike;
}

interface PackageManagerRuntime {
  new (options: {
    cwd: string;
    agentDir: string;
    settingsManager: SettingsManagerLike;
  }): PackageManagerLike;
}

const settingsManagerRuntime = SettingsManager as SettingsManagerRuntime;
const packageManagerRuntime = DefaultPackageManager as PackageManagerRuntime;
const agentDirRuntime = getAgentDir as () => string;

function createServices(ctx: HubContext): HubServices {
  const agentDir = agentDirRuntime();
  const settingsManager = settingsManagerRuntime.create(ctx.cwd, agentDir);
  const packageManager = new packageManagerRuntime({
    cwd: ctx.cwd,
    agentDir,
    settingsManager,
  });
  return { agentDir, settingsManager, packageManager };
}

function reportError(ctx: HubContext, error: unknown): void {
  const message = error instanceof Error ? error.message : String(error);
  ctx.ui.notify(`Settings hub failed: ${message}`, "error");
}

async function runHub(
  pi: PiApi,
  ctx: HubContext,
  dispatch: (action: HubAction) => void | Promise<void>,
): Promise<void> {
  const action = await openSettingsHub(pi, ctx, createServices(ctx));
  if (action) await dispatch(action);
}

export default function settingsHubExtension(pi: PiApi): void {
  const state: SettingsInterceptorState = {
    bypassSettingsOnce: false,
    settingsOpen: false,
  };

  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI || ctx.mode !== "tui") return;

    const previousFactory = ctx.ui.getEditorComponent();
    ctx.ui.setEditorComponent((tui, editorTheme, keybindings) => {
      const editor = previousFactory
        ? previousFactory(tui, editorTheme, keybindings)
        : new CustomEditor(tui, editorTheme, keybindings);

      return installSettingsInterceptor(
        editor,
        state,
        async (delegate: SubmitHandler) => {
          await runHub(pi, ctx, (action) => {
            if (action.kind === "submit") {
              delegate(action.text);
            } else {
              ctx.ui.setEditorText(action.text);
              ctx.ui.notify("Command placed in the editor; add arguments if needed, then press Enter", "info");
            }
          });
        },
        (error) => reportError(ctx, error),
      );
    });
  });

  pi.registerCommand("settings-hub", {
    description: "Open the unified Pi, package, tool, and extension settings hub",
    handler: async (_args: string, ctx: CommandContext) => {
      if (!ctx.hasUI || ctx.mode !== "tui") {
        ctx.ui.notify("The settings hub requires interactive TUI mode", "warning");
        return;
      }

      await runHub(pi, ctx, async (action) => {
        if (action.kind === "submit" && action.text === "/reload") {
          await ctx.reload();
          return;
        }

        if (action.kind === "submit" && action.text === "/settings") {
          state.bypassSettingsOnce = true;
        }
        ctx.ui.setEditorText(action.text);
        ctx.ui.notify("Selection placed in the editor; press Enter to open it", "info");
      }).catch((error) => reportError(ctx, error));
    },
  });
}
