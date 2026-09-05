import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { parseJsonc, validateJsonObject, writeConfigFileAtomic } from "./jsonc.js";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((path) => rm(path, { recursive: true, force: true })));
});

describe("JSONC support", () => {
  test("accepts comments and trailing commas without damaging strings", () => {
    const value = parseJsonc(`{
      // line comment
      "url": "https://example.test/a,}",
      "nested": {
        /* block comment */
        "enabled": true,
      },
    }`) as { url: string; nested: { enabled: boolean } };

    expect(value.url).toBe("https://example.test/a,}");
    expect(value.nested.enabled).toBe(true);
  });

  test("requires a top-level object", () => {
    expect(() => validateJsonObject("[1, 2, 3]")).toThrow("top level");
  });

  test("atomically preserves an existing file mode", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pi-settings-hub-"));
    temporaryDirectories.push(directory);
    const path = join(directory, "config.json");
    await writeFile(path, "{}\n", { mode: 0o640 });

    await writeConfigFileAtomic(path, '{"enabled": true}');

    expect(await readFile(path, "utf8")).toBe('{"enabled": true}\n');
    expect((await stat(path)).mode & 0o777).toBe(0o640);
  });
});
