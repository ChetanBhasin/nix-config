import type { Component, EditorComponent, EditorTheme, TUI } from "@earendil-works/pi-tui";

export type NotifyLevel = "info" | "warning" | "error";

export interface ThemeLike {
  fg(color: string, text: string): string;
  bold(text: string): string;
}

export type EditorFactory = (
  tui: TUI,
  theme: EditorTheme,
  keybindings: unknown,
) => EditorComponent;

export interface HubUi {
  readonly theme: ThemeLike;
  custom<T>(
    factory: (
      tui: TUI,
      theme: ThemeLike,
      keybindings: unknown,
      done: (value: T) => void,
    ) => Component,
  ): Promise<T>;
  confirm(title: string, message: string): Promise<boolean>;
  editor(title: string, prefill?: string): Promise<string | undefined>;
  notify(message: string, level?: NotifyLevel): void;
  setEditorText(text: string): void;
  getEditorComponent(): EditorFactory | undefined;
  setEditorComponent(factory: EditorFactory | undefined): void;
}

export interface HubContext {
  cwd: string;
  hasUI: boolean;
  mode: string;
  isProjectTrusted(): boolean;
  ui: HubUi;
}

export interface CommandContext extends HubContext {
  reload(): Promise<void>;
}

export interface CommandInfo {
  name: string;
  description?: string;
  source: "extension" | "prompt" | "skill";
}

export interface ToolInfo {
  name: string;
  label: string;
  description: string;
}

export interface PiApi {
  on(event: "session_start", handler: (_event: unknown, ctx: HubContext) => void | Promise<void>): void;
  registerCommand(
    name: string,
    options: {
      description: string;
      handler: (args: string, ctx: CommandContext) => void | Promise<void>;
    },
  ): void;
  getCommands(): CommandInfo[];
  getAllTools(): ToolInfo[];
  getActiveTools(): string[];
  setActiveTools(names: string[]): void;
}

export type HubAction =
  | { kind: "submit"; text: string }
  | { kind: "prefill"; text: string };

export type SubmitHandler = (text: string) => void;
