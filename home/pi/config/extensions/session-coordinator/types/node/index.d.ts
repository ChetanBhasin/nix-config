declare namespace NodeJS {
  interface Timeout {
    unref(): this;
  }
}

declare const Buffer: {
  byteLength(value: string, encoding?: "utf8"): number;
};

declare const console: {
  error(...values: unknown[]): void;
};

declare const process: {
  env: Record<string, string | undefined>;
  pid: number;
  kill(pid: number, signal?: number | string): void;
};

declare function clearInterval(timer: NodeJS.Timeout | undefined): void;
declare function clearTimeout(timer: NodeJS.Timeout | undefined): void;
declare function setInterval(callback: () => void, delay?: number): NodeJS.Timeout;
declare function setTimeout(callback: () => void, delay?: number): NodeJS.Timeout;

declare module "node:crypto" {
  export function randomUUID(): string;
}

declare module "node:fs/promises" {
  export interface Dirent {
    name: string;
    isFile(): boolean;
  }

  export interface Stats {
    mtimeMs: number;
    size: number;
  }

  export function chmod(path: string, mode: number): Promise<void>;
  export function mkdir(
    path: string,
    options?: { mode?: number; recursive?: boolean },
  ): Promise<string | undefined>;
  export function readFile(path: string, encoding: "utf8"): Promise<string>;
  export function readdir(path: string, options: { withFileTypes: true }): Promise<Dirent[]>;
  export function rename(oldPath: string, newPath: string): Promise<void>;
  export function rm(path: string, options?: { force?: boolean; recursive?: boolean }): Promise<void>;
  export function stat(path: string): Promise<Stats>;
  export function writeFile(
    path: string,
    data: string,
    options?: string | { encoding?: string; mode?: number },
  ): Promise<void>;
}

declare module "node:os" {
  export function homedir(): string;
}

declare module "node:path" {
  export function dirname(path: string): string;
  export function join(...paths: string[]): string;
}
