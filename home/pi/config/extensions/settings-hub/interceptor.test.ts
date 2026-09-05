import { describe, expect, test } from "bun:test";
import type { EditorComponent } from "@earendil-works/pi-tui";
import { installSettingsInterceptor, type SettingsInterceptorState } from "./interceptor.js";

function fakeEditor(): EditorComponent {
  return {
    getText: () => "",
    setText: () => undefined,
    handleInput: () => undefined,
    invalidate: () => undefined,
    render: () => [],
  };
}

function tick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("settings submit interception", () => {
  test("delegates ordinary input and opens the hub for exact /settings", async () => {
    const editor = fakeEditor();
    const state: SettingsInterceptorState = { bypassSettingsOnce: false, settingsOpen: false };
    const delegated: string[] = [];
    let opened = 0;

    installSettingsInterceptor(
      editor,
      state,
      async (delegate) => {
        opened += 1;
        delegate("/footer");
      },
      (error) => { throw error; },
    );
    editor.onSubmit = (text) => delegated.push(text);

    editor.onSubmit?.("hello");
    editor.onSubmit?.(" /settings ");
    await tick();

    expect(opened).toBe(1);
    expect(delegated).toEqual(["hello", "/footer"]);
    expect(state.settingsOpen).toBe(false);
  });

  test("can bypass the hub once to reach Pi's native settings", async () => {
    const editor = fakeEditor();
    const state: SettingsInterceptorState = { bypassSettingsOnce: true, settingsOpen: false };
    const delegated: string[] = [];

    installSettingsInterceptor(editor, state, async () => undefined, (error) => { throw error; });
    editor.onSubmit = (text) => delegated.push(text);
    editor.onSubmit?.("/settings");
    await tick();

    expect(delegated).toEqual(["/settings"]);
    expect(state.bypassSettingsOnce).toBe(false);
  });
});
