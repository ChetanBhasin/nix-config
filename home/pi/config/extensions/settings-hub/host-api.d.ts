declare module "@earendil-works/pi-coding-agent" {
  import type { Component, EditorComponent, EditorTheme, TUI } from "@earendil-works/pi-tui";

  export const CustomEditor: {
    new (tui: TUI, theme: EditorTheme, keybindings: unknown): EditorComponent;
  };
  export class DynamicBorder implements Component {
    constructor(color?: (text: string) => string);
    invalidate(): void;
    render(width: number): string[];
  }
  export const DefaultPackageManager: unknown;
  export const SettingsManager: unknown;
  export function getAgentDir(): string;
}

declare module "bun:test" {
  export function describe(name: string, body: () => void): void;
  export function test(name: string, body: () => void | Promise<void>): void;
  export function afterEach(body: () => void | Promise<void>): void;
  export function expect(value: unknown): {
    toBe(expected: unknown): void;
    toEqual(expected: unknown): void;
    toThrow(expected?: string | RegExp): void;
  };
}
