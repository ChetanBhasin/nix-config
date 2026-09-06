import { describe, expect, test } from "bun:test";
import {
  flushSettings,
  toggleGlobalResource,
  type GlobalSettings,
  type SettingsManagerLike,
  type SettingsWriteError,
} from "./resources.js";

class FakeSettingsManager implements SettingsManagerLike {
  constructor(
    public settings: GlobalSettings,
    private errors: SettingsWriteError[] = [],
  ) {}

  getGlobalSettings(): GlobalSettings { return this.settings; }
  setPackages(packages: NonNullable<GlobalSettings["packages"]>): void { this.settings.packages = packages; }
  setExtensionPaths(paths: string[]): void { this.settings.extensions = paths; }
  setSkillPaths(paths: string[]): void { this.settings.skills = paths; }
  setPromptTemplatePaths(paths: string[]): void { this.settings.prompts = paths; }
  setThemePaths(paths: string[]): void { this.settings.themes = paths; }
  setDefaultTools(): void {}
  async flush(): Promise<void> {}
  drainErrors(): SettingsWriteError[] {
    const errors = this.errors;
    this.errors = [];
    return errors;
  }
}

describe("global resource toggles", () => {
  test("adds explicit disable and enable patterns for auto-discovered resources", () => {
    const manager = new FakeSettingsManager({});
    const resource = {
      path: "/home/test/.pi/agent/themes/gruvbox-night.json",
      enabled: true,
      metadata: {
        source: "auto",
        scope: "user" as const,
        origin: "top-level" as const,
        baseDir: "/home/test/.pi/agent",
      },
    };

    toggleGlobalResource(manager, "themes", resource, false, "/home/test/.pi/agent");
    expect(manager.settings.themes).toEqual(["-themes/gruvbox-night.json"]);

    toggleGlobalResource(manager, "themes", resource, true, "/home/test/.pi/agent");
    expect(manager.settings.themes).toEqual(["+themes/gruvbox-night.json"]);
  });

  test("converts a package source into a filtered package entry", () => {
    const source = "npm:example-extension@1.2.3";
    const manager = new FakeSettingsManager({ packages: [source] });
    const resource = {
      path: "/home/test/.pi/agent/npm/node_modules/example-extension/dist/index.js",
      enabled: true,
      metadata: {
        source,
        scope: "user" as const,
        origin: "package" as const,
        baseDir: "/home/test/.pi/agent/npm/node_modules/example-extension",
      },
    };

    toggleGlobalResource(manager, "extensions", resource, false, "/home/test/.pi/agent");
    expect(manager.settings.packages).toEqual([
      { source, extensions: ["-dist/index.js"] },
    ]);

    toggleGlobalResource(manager, "extensions", resource, true, "/home/test/.pi/agent");
    expect(manager.settings.packages).toEqual([
      { source, extensions: ["+dist/index.js"] },
    ]);
  });
});

describe("settings persistence", () => {
  test("surfaces queued write errors after flushing", async () => {
    const manager = new FakeSettingsManager({}, [
      { scope: "global", path: "/tmp/settings.json", error: new Error("permission denied") },
    ]);
    let message = "";

    try {
      await flushSettings(manager);
    } catch (error) {
      message = error instanceof Error ? error.message : String(error);
    }

    expect(message).toBe("global (/tmp/settings.json): permission denied");
  });
});
