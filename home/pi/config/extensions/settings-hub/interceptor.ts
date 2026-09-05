import type { EditorComponent } from "@earendil-works/pi-tui";
import type { SubmitHandler } from "./types.js";

export interface SettingsInterceptorState {
  bypassSettingsOnce: boolean;
  settingsOpen: boolean;
}

/**
 * Wrap an editor's submit callback without changing its rendering or input behavior.
 * Pi assigns the real callback after constructing the editor, so this accessor captures
 * that later assignment and keeps the built-in handler available for delegation.
 */
export function installSettingsInterceptor(
  editor: EditorComponent,
  state: SettingsInterceptorState,
  openSettings: (delegate: SubmitHandler) => Promise<void>,
  reportError: (error: unknown) => void,
): EditorComponent {
  let delegate = editor.onSubmit;

  Object.defineProperty(editor, "onSubmit", {
    configurable: true,
    enumerable: true,
    get(): SubmitHandler | undefined {
      const currentDelegate = delegate;
      if (!currentDelegate) return undefined;

      return (text: string): void => {
        const isSettings = text.trim() === "/settings";

        if (state.bypassSettingsOnce) {
          state.bypassSettingsOnce = false;
          currentDelegate(text);
          return;
        }

        if (!isSettings) {
          currentDelegate(text);
          return;
        }

        if (state.settingsOpen) return;
        state.settingsOpen = true;

        void openSettings(currentDelegate)
          .catch(reportError)
          .finally(() => {
            state.settingsOpen = false;
          });
      };
    },
    set(next: SubmitHandler | undefined): void {
      delegate = next;
    },
  });

  return editor;
}
