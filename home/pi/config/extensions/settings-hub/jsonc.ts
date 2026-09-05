import { chmod, lstat, mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

function stripComments(text: string): string {
  let result = "";
  let inString = false;
  let escaped = false;
  let inLineComment = false;
  let inBlockComment = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    const next = text[index + 1];

    if (inLineComment) {
      if (character === "\n" || character === "\r") {
        inLineComment = false;
        result += character;
      } else {
        result += " ";
      }
      continue;
    }

    if (inBlockComment) {
      if (character === "*" && next === "/") {
        result += "  ";
        index += 1;
        inBlockComment = false;
      } else {
        result += character === "\n" || character === "\r" ? character : " ";
      }
      continue;
    }

    if (inString) {
      result += character;
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === '"') {
        inString = false;
      }
      continue;
    }

    if (character === '"') {
      inString = true;
      result += character;
    } else if (character === "/" && next === "/") {
      result += "  ";
      index += 1;
      inLineComment = true;
    } else if (character === "/" && next === "*") {
      result += "  ";
      index += 1;
      inBlockComment = true;
    } else {
      result += character;
    }
  }

  if (inBlockComment) throw new Error("Unterminated block comment");
  return result;
}

function stripTrailingCommas(text: string): string {
  const characters = [...text];
  let inString = false;
  let escaped = false;

  for (let index = 0; index < characters.length; index += 1) {
    const character = characters[index];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === '"') {
        inString = false;
      }
      continue;
    }

    if (character === '"') {
      inString = true;
      continue;
    }

    if (character !== ",") continue;

    let lookahead = index + 1;
    while (lookahead < characters.length && /\s/.test(characters[lookahead])) {
      lookahead += 1;
    }

    if (characters[lookahead] === "}" || characters[lookahead] === "]") {
      characters[index] = " ";
    }
  }

  return characters.join("");
}

export function parseJsonc(text: string): unknown {
  const withoutBom = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  return JSON.parse(stripTrailingCommas(stripComments(withoutBom)));
}

export function validateJsonObject(text: string): void {
  const value = parseJsonc(text);
  if (value === null || Array.isArray(value) || typeof value !== "object") {
    throw new Error("Configuration must contain a JSON object at the top level");
  }
}

export async function readConfigFile(path: string): Promise<string> {
  try {
    return await readFile(path, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return "{}\n";
    throw error;
  }
}

export async function writeConfigFileAtomic(path: string, content: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true });

  let mode = 0o600;
  try {
    const metadata = await lstat(path);
    if (metadata.isSymbolicLink()) {
      throw new Error(`Refusing to replace symbolic link: ${path}`);
    }
    mode = metadata.mode & 0o777;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }

  const temporaryPath = `${path}.settings-hub.${process.pid}.${Date.now()}.tmp`;
  const normalized = content.endsWith("\n") ? content : `${content}\n`;

  try {
    await writeFile(temporaryPath, normalized, { encoding: "utf8", mode });
    await chmod(temporaryPath, mode);
    await rename(temporaryPath, path);
  } catch (error) {
    await unlink(temporaryPath).catch(() => undefined);
    throw error;
  }
}
