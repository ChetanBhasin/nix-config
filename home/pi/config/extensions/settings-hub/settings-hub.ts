import { join } from "node:path";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";
import {
  Container,
  SelectList,
  SettingsList,
  Text,
  type SelectItem,
  type SettingItem,
} from "@earendil-works/pi-tui";
import { readConfigFile, validateJsonObject, writeConfigFileAtomic } from "./jsonc.js";
import {
  flushSettings,
  flattenUserResources,
  resourceLabel,
  sourceLabel,
  toggleGlobalResource,
  type PackageManagerLike,
  type ResourceType,
  type ResolvedResource,
  type SettingsManagerLike,
} from "./resources.js";
import type { HubAction, HubContext, PiApi } from "./types.js";

export interface HubServices {
  agentDir: string;
  settingsManager: SettingsManagerLike;
  packageManager: PackageManagerLike;
}

interface ConfigTarget {
  id: string;
  label: string;
  description: string;
  path: string;
}

const RESOURCE_ORDER: Record<ResourceType, number> = {
  extensions: 0,
  skills: 1,
  prompts: 2,
  themes: 3,
};

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}


async function choose(
  ctx: HubContext,
  title: string,
  subtitle: string,
  items: SelectItem[],
): Promise<string | undefined> {
  return ctx.ui.custom<string | undefined>((tui, theme, _keybindings, done) => {
    const container = new Container();
    container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));
    container.addChild(new Text(theme.fg("accent", theme.bold(title))));
    container.addChild(new Text(theme.fg("muted", subtitle)));

    const list = new SelectList(items, Math.min(items.length, 14), {
      selectedPrefix: (text) => theme.fg("accent", text),
      selectedText: (text) => theme.fg("accent", text),
      description: (text) => theme.fg("muted", text),
      scrollInfo: (text) => theme.fg("dim", text),
      noMatch: (text) => theme.fg("warning", text),
    });
    list.onSelect = (item) => done(item.value);
    list.onCancel = () => done(undefined);
    container.addChild(list);
    container.addChild(new Text(theme.fg("dim", "↑↓ navigate • enter select • esc back")));
    container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));

    return {
      render: (width: number) => container.render(width),
      invalidate: () => container.invalidate(),
      handleInput: (data: string) => {
        list.handleInput(data);
        tui.requestRender();
      },
    };
  });
}

function panel(
  ctx: HubContext,
  title: string,
  subtitle: string,
  items: SettingItem[],
  onChange: (id: string, value: string) => void,
): Promise<void> {
  return ctx.ui.custom<void>((tui, theme, _keybindings, done) => {
    const container = new Container();
    container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));
    container.addChild(new Text(theme.fg("accent", theme.bold(title))));
    container.addChild(new Text(theme.fg("muted", subtitle)));

    const list = new SettingsList(
      items,
      Math.min(items.length, 16),
      {
        label: (text, selected) => theme.fg(selected ? "accent" : "text", text),
        value: (text, selected) => theme.fg(selected ? "accent" : "muted", text),
        description: (text) => theme.fg("muted", text),
        cursor: theme.fg("accent", "› "),
        hint: (text) => theme.fg("dim", text),
      },
      (id, value) => {
        onChange(id, value);
        tui.requestRender();
      },
      () => done(undefined),
      { enableSearch: true },
    );

    container.addChild(list);
    container.addChild(new Text(theme.fg("dim", "enter/space change • / search • esc back")));
    container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));

    return {
      render: (width: number) => container.render(width),
      invalidate: () => container.invalidate(),
      handleInput: (data: string) => {
        list.handleInput(data);
        tui.requestRender();
      },
    };
  });
}

async function showToolSettings(
  pi: PiApi,
  ctx: HubContext,
  settingsManager: SettingsManagerLike,
): Promise<void> {
  const active = new Set(pi.getActiveTools());
  const tools = pi.getAllTools().sort((left, right) => left.label.localeCompare(right.label));
  const byId = new Map(tools.map((tool) => [tool.name, tool]));
  let dirty = false;
  const items: SettingItem[] = tools.map((tool) => ({
    id: tool.name,
    label: tool.label || tool.name,
    description: `${tool.name} — ${tool.description}`,
    currentValue: active.has(tool.name) ? "enabled" : "disabled",
    values: ["enabled", "disabled"],
  }));

  await panel(ctx, "Tool Defaults", "Changes apply to this session and future Pi sessions.", items, (id, value) => {
    if (!byId.has(id)) return;
    if (value === "enabled") active.add(id);
    else active.delete(id);

    const ordered = tools.map((tool) => tool.name).filter((name) => active.has(name));
    pi.setActiveTools(ordered);
    settingsManager.setDefaultTools(ordered);
    dirty = true;
  });

  if (!dirty) return;
  try {
    await flushSettings(settingsManager);
    ctx.ui.notify("Tool defaults saved", "info");
  } catch (error) {
    ctx.ui.notify(`Active tools changed, but defaults could not be saved: ${errorMessage(error)}`, "error");
  }
}

function packageDisplayName(source: string): string {
  const display = sourceLabel(source);
  if (!source.startsWith("npm:")) return display;
  const versionSeparator = display.lastIndexOf("@");
  return versionSeparator > 0 ? display.slice(0, versionSeparator) : display;
}

function resourceDisplayLabel(type: ResourceType, resource: ResolvedResource): string {
  const typeLabel = type.slice(0, -1);
  const fileLabel = resourceLabel(type, resource.path);
  const name = resource.metadata.origin === "package" && fileLabel === "index"
    ? packageDisplayName(resource.metadata.source)
    : fileLabel;
  return `${typeLabel} · ${name}`;
}

async function showResourceSettings(
  ctx: HubContext,
  services: HubServices,
): Promise<boolean> {
  let resolved;
  try {
    resolved = await services.packageManager.resolve(async () => "skip");
  } catch (error) {
    ctx.ui.notify(`Could not resolve Pi resources: ${errorMessage(error)}`, "error");
    return false;
  }

  const entries = flattenUserResources(resolved).sort((left, right) =>
    RESOURCE_ORDER[left.type] - RESOURCE_ORDER[right.type]
    || resourceDisplayLabel(left.type, left.resource).localeCompare(resourceDisplayLabel(right.type, right.resource))
  );

  if (entries.length === 0) {
    ctx.ui.notify("No user-scoped resources were found", "warning");
    return false;
  }

  let dirty = false;
  const byId = new Map<string, (typeof entries)[number]>();
  const items: SettingItem[] = entries.map((entry, index) => {
    const id = `${entry.type}:${index}`;
    byId.set(id, entry);
    return {
      id,
      label: resourceDisplayLabel(entry.type, entry.resource),
      description: `${sourceLabel(entry.resource.metadata.source)} — reload required`,
      currentValue: entry.resource.enabled ? "enabled" : "disabled",
      values: ["enabled", "disabled"],
    };
  });

  await panel(
    ctx,
    "Packages & Resources",
    "Enable or disable global extensions, skills, prompts, and themes.",
    items,
    (id, value) => {
      const entry = byId.get(id);
      if (!entry) return;
      try {
        toggleGlobalResource(
          services.settingsManager,
          entry.type,
          entry.resource,
          value === "enabled",
          services.agentDir,
        );
        dirty = true;
      } catch (error) {
        ctx.ui.notify(errorMessage(error), "error");
      }
    },
  );

  if (!dirty) return false;
  try {
    await flushSettings(services.settingsManager);
    ctx.ui.notify("Resource settings saved; reload Pi to apply them", "info");
    return true;
  } catch (error) {
    ctx.ui.notify(`Resource settings could not be saved: ${errorMessage(error)}`, "error");
    return false;
  }
}

function configTargets(agentDir: string): ConfigTarget[] {
  return [
    {
      id: "pi-settings",
      label: "Pi settings.json",
      description: "Advanced editor for Pi's complete global settings",
      path: join(agentDir, "settings.json"),
    },
    {
      id: "models",
      label: "Custom models",
      description: "Provider and model definitions",
      path: join(agentDir, "models.json"),
    },
    {
      id: "keybindings",
      label: "Keybindings",
      description: "Global keyboard shortcut overrides",
      path: join(agentDir, "keybindings.json"),
    },
    {
      id: "browser",
      label: "Agent Browser",
      description: "Browser extension configuration",
      path: join(agentDir, "extensions", "config", "browser.json"),
    },
    {
      id: "lens",
      label: "Pi Lens",
      description: "Diagnostics, guards, tools, and widget behavior",
      path: join(agentDir, "extensions", "config", "lens-global.json"),
    },
    {
      id: "magic-context",
      label: "Magic Context",
      description: "Compaction, memory, historian, and storage behavior",
      path: join(agentDir, "extensions", "config", "magic-context.jsonc"),
    },
    {
      id: "subagents",
      label: "Pi Subagents",
      description: "Concurrency, output, missions, and runtime limits",
      path: join(agentDir, "extensions", "subagent", "config.json"),
    },
    {
      id: "footer",
      label: "Pi Footer",
      description: "Footer layout and content",
      path: join(agentDir, "extensions", "pi-footer.json"),
    },
    {
      id: "gruvbox-night",
      label: "Gruvbox Night theme",
      description: "Active Pi color theme",
      path: join(agentDir, "themes", "gruvbox-night.json"),
    },
  ];
}

async function editConfigTarget(ctx: HubContext, target: ConfigTarget): Promise<boolean> {
  let original: string;
  try {
    original = await readConfigFile(target.path);
  } catch (error) {
    ctx.ui.notify(`Could not read ${target.path}: ${errorMessage(error)}`, "error");
    return false;
  }

  const edited = await ctx.ui.editor(`${target.label} — JSON/JSONC`, original);
  if (edited === undefined || edited === original || `${edited}\n` === original) return false;

  try {
    validateJsonObject(edited);
  } catch (error) {
    ctx.ui.notify(`Invalid configuration: ${errorMessage(error)}`, "error");
    return false;
  }

  const confirmed = await ctx.ui.confirm(
    `Save ${target.label}?`,
    `Write validated configuration to:\n${target.path}`,
  );
  if (!confirmed) return false;

  try {
    await writeConfigFileAtomic(target.path, edited);
    ctx.ui.notify(`${target.label} saved`, "info");
    return true;
  } catch (error) {
    ctx.ui.notify(`Could not save ${target.path}: ${errorMessage(error)}`, "error");
    return false;
  }
}

async function showAdvancedConfigMenu(
  ctx: HubContext,
  agentDir: string,
): Promise<boolean> {
  const targets = configTargets(agentDir);
  const selected = await choose(
    ctx,
    "Advanced Configuration",
    "Raw JSON/JSONC editing with validation and atomic saves.",
    targets.map((target) => ({
      value: target.id,
      label: target.label,
      description: target.description,
    })),
  );
  if (!selected) return false;
  const target = targets.find((candidate) => candidate.id === selected);
  return target ? editConfigTarget(ctx, target) : false;
}

async function showModelMenu(ctx: HubContext): Promise<HubAction | undefined> {
  const selected = await choose(ctx, "Models & Accounts", "Open Pi's native and extension-provided model controls.", [
    { value: "/model", label: "Active model", description: "Select the model for this session" },
    { value: "/scoped-models", label: "Scoped models", description: "Configure models for different workloads" },
    { value: "/accounts", label: "Accounts", description: "Manage provider accounts and credentials" },
    { value: "/usage", label: "Usage", description: "View account and model usage" },
  ]);
  return selected ? { kind: "submit", text: selected } : undefined;
}

async function showAutoModeMenu(ctx: HubContext): Promise<HubAction | undefined> {
  const selected = await choose(ctx, "Auto Mode", "Control unattended mode for this running Pi process.", [
    { value: "/auto status", label: "Show status", description: "Display the current process state" },
    { value: "/auto on", label: "Enable", description: "Suppress questions and approve validated spawn budgets" },
    { value: "/auto off", label: "Disable", description: "Restore interactive confirmations" },
  ]);
  return selected ? { kind: "submit", text: selected } : undefined;
}

async function showLensMenu(ctx: HubContext): Promise<HubAction | undefined> {
  const selected = await choose(ctx, "Pi Lens", "Configure or toggle Pi Lens features.", [
    { value: "/lens-config", label: "Lens configuration", description: "Open Pi Lens's configuration UI" },
    { value: "/lens-toggle", label: "Toggle Lens", description: "Enable or disable the extension" },
    { value: "/lens-lsp-toggle", label: "Toggle LSP", description: "Enable or disable LSP integration" },
    { value: "/lens-widget-toggle", label: "Toggle widget", description: "Show or hide the diagnostics widget" },
    { value: "/lens-context-toggle", label: "Toggle context", description: "Enable or disable context injection" },
    { value: "/lens-delta-toggle", label: "Toggle delta", description: "Enable or disable delta reporting" },
  ]);
  return selected ? { kind: "submit", text: selected } : undefined;
}

async function showExtensionMenu(ctx: HubContext): Promise<HubAction | "advanced" | undefined> {
  const selected = await choose(ctx, "Extensions", "Open settings screens and runtime controls supplied by extensions.", [
    { value: "/footer", label: "Pi Footer", description: "Configure footer visibility and layout" },
    { value: "/subagents", label: "Pi Subagents", description: "Open the subagent administration screen" },
    { value: "/accounts", label: "Accounts", description: "Manage provider accounts" },
    { value: "auto-mode", label: "Auto Mode", description: "Unattended execution controls" },
    { value: "lens", label: "Pi Lens", description: "Diagnostics, LSP, and widget controls" },
    { value: "/toggle-auto-read", label: "Hashline auto-read", description: "Toggle automatic reads after edits" },
    { value: "advanced", label: "Advanced config files", description: "Edit extension JSON/JSONC configuration" },
    { value: "all-commands", label: "All extension commands", description: "Browse every command registered by an extension" },
  ]);

  if (!selected) return undefined;
  if (selected === "auto-mode") return showAutoModeMenu(ctx);
  if (selected === "lens") return showLensMenu(ctx);
  if (selected === "advanced") return "advanced";
  if (selected === "all-commands") return { kind: "prefill", text: "" };
  return { kind: "submit", text: selected };
}

async function showAllCommands(pi: PiApi, ctx: HubContext): Promise<HubAction | undefined> {
  const commands = pi.getCommands()
    .filter((command) => command.source === "extension" && command.name !== "settings-hub")
    .sort((left, right) => left.name.localeCompare(right.name));
  const selected = await choose(
    ctx,
    "Extension Commands",
    "Select a command to place it in the editor; add arguments, then press Enter.",
    commands.map((command) => ({
      value: command.name,
      label: `/${command.name}`,
      description: command.description || "Extension command",
    })),
  );
  return selected ? { kind: "prefill", text: `/${selected} ` } : undefined;
}

export async function openSettingsHub(
  pi: PiApi,
  ctx: HubContext,
  services: HubServices,
): Promise<HubAction | undefined> {
  let reloadNeeded = false;

  while (true) {
    const selected = await choose(
      ctx,
      "Pi Settings",
      reloadNeeded
        ? "Control center — unsynchronized resource/config changes require reload."
        : "Control center for Pi, packages, tools, and extensions.",
      [
        { value: "core", label: "Core Pi settings", description: "Open Pi's native settings screen" },
        { value: "models", label: "Models & accounts", description: "Models, scoped models, providers, and usage" },
        { value: "tools", label: "Tool defaults", description: "Enable tools now and for future sessions" },
        { value: "resources", label: "Packages & resources", description: "Extensions, skills, prompts, and themes" },
        { value: "extensions", label: "Extension settings", description: "Plugin screens and runtime controls" },
        { value: "advanced", label: "Advanced configuration", description: "Validated JSON/JSONC editors" },
        { value: "reload", label: "Reload Pi", description: "Apply saved extension and resource changes" },
      ],
    );

    if (!selected) {
      if (reloadNeeded && await ctx.ui.confirm("Reload Pi now?", "Some saved changes require an extension reload.")) {
        return { kind: "submit", text: "/reload" };
      }
      return undefined;
    }

    if (selected === "core") return { kind: "submit", text: "/settings" };
    if (selected === "models") {
      const action = await showModelMenu(ctx);
      if (action) return action;
      continue;
    }
    if (selected === "tools") {
      await showToolSettings(pi, ctx, services.settingsManager);
      continue;
    }
    if (selected === "resources") {
      reloadNeeded = await showResourceSettings(ctx, services) || reloadNeeded;
      continue;
    }
    if (selected === "extensions") {
      const action = await showExtensionMenu(ctx);
      if (action === "advanced") {
        reloadNeeded = await showAdvancedConfigMenu(ctx, services.agentDir) || reloadNeeded;
      } else if (action?.kind === "prefill" && action.text === "") {
        const command = await showAllCommands(pi, ctx);
        if (command) return command;
      } else if (action) {
        return action;
      }
      continue;
    }
    if (selected === "advanced") {
      reloadNeeded = await showAdvancedConfigMenu(ctx, services.agentDir) || reloadNeeded;
      continue;
    }
    if (selected === "reload") return { kind: "submit", text: "/reload" };
  }
}
