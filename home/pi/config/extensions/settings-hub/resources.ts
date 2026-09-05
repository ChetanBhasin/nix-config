import { basename, dirname, extname, relative } from "node:path";

export const RESOURCE_TYPES = ["extensions", "skills", "prompts", "themes"] as const;
export type ResourceType = (typeof RESOURCE_TYPES)[number];

export interface PathMetadata {
  source: string;
  scope: "user" | "project" | "temporary";
  origin: "package" | "top-level";
  baseDir?: string;
}

export interface ResolvedResource {
  path: string;
  enabled: boolean;
  metadata: PathMetadata;
}

export type PackageEntry =
  | string
  | {
      source: string;
      autoload?: boolean;
      extensions?: string[];
      skills?: string[];
      prompts?: string[];
      themes?: string[];
    };

export interface GlobalSettings {
  packages?: PackageEntry[];
  extensions?: string[];
  skills?: string[];
  prompts?: string[];
  themes?: string[];
}

export interface SettingsWriteError {
  scope: "global" | "project";
  path?: string;
  error: Error;
}

export interface SettingsManagerLike {
  getGlobalSettings(): GlobalSettings;
  setPackages(packages: PackageEntry[]): void;
  setExtensionPaths(paths: string[]): void;
  setSkillPaths(paths: string[]): void;
  setPromptTemplatePaths(paths: string[]): void;
  setThemePaths(paths: string[]): void;
  setDefaultTools(tools: string[]): void;
  flush(): Promise<void>;
  drainErrors(): SettingsWriteError[];
}

export async function flushSettings(settingsManager: SettingsManagerLike): Promise<void> {
  await settingsManager.flush();
  const errors = settingsManager.drainErrors();
  if (errors.length === 0) return;

  const details = errors.map(({ scope, path, error }) =>
    `${scope}${path ? ` (${path})` : ""}: ${error.message}`
  ).join("; ");
  throw new Error(details);
}

export interface ResolvedPaths {
  extensions: ResolvedResource[];
  skills: ResolvedResource[];
  prompts: ResolvedResource[];
  themes: ResolvedResource[];
}

export interface PackageManagerLike {
  resolve(onMissing?: (source: string) => Promise<"install" | "skip" | "error">): Promise<ResolvedPaths>;
}

function stripPatternPrefix(pattern: string): string {
  return /^[!+-]/.test(pattern) ? pattern.slice(1) : pattern;
}

function resourcePattern(item: ResolvedResource, agentDir: string): string {
  return relative(item.metadata.baseDir ?? agentDir, item.path);
}

function packageResourcePattern(item: ResolvedResource): string {
  return relative(item.metadata.baseDir ?? dirname(item.path), item.path);
}

function setTopLevelPaths(
  settingsManager: SettingsManagerLike,
  type: ResourceType,
  paths: string[],
): void {
  switch (type) {
    case "extensions":
      settingsManager.setExtensionPaths(paths);
      break;
    case "skills":
      settingsManager.setSkillPaths(paths);
      break;
    case "prompts":
      settingsManager.setPromptTemplatePaths(paths);
      break;
    case "themes":
      settingsManager.setThemePaths(paths);
      break;
  }
}

export function toggleGlobalResource(
  settingsManager: SettingsManagerLike,
  type: ResourceType,
  item: ResolvedResource,
  enabled: boolean,
  agentDir: string,
): void {
  if (item.metadata.scope !== "user") {
    throw new Error("Only user-scoped resources can be changed from this screen");
  }

  const settings = settingsManager.getGlobalSettings();

  if (item.metadata.origin === "top-level") {
    const pattern = resourcePattern(item, agentDir);
    const current = settings[type] ?? [];
    const updated = current.filter((entry) => stripPatternPrefix(entry) !== pattern);
    updated.push(`${enabled ? "+" : "-"}${pattern}`);
    setTopLevelPaths(settingsManager, type, updated);
    item.enabled = enabled;
    return;
  }

  const packages = [...(settings.packages ?? [])];
  const packageIndex = packages.findIndex((entry) =>
    (typeof entry === "string" ? entry : entry.source) === item.metadata.source
  );

  if (packageIndex < 0) {
    throw new Error(`Package is not present in global settings: ${item.metadata.source}`);
  }

  const existing = packages[packageIndex];
  const packageEntry = typeof existing === "string" ? { source: existing } : { ...existing };
  const pattern = packageResourcePattern(item);
  const current = packageEntry[type] ?? [];
  const updated = current.filter((entry) => stripPatternPrefix(entry) !== pattern);
  updated.push(`${enabled ? "+" : "-"}${pattern}`);
  packageEntry[type] = updated;

  const hasFilters = RESOURCE_TYPES.some((key) => packageEntry[key] !== undefined);
  packages[packageIndex] = hasFilters ? packageEntry : packageEntry.source;
  settingsManager.setPackages(packages);
  item.enabled = enabled;
}

export function flattenUserResources(resolved: ResolvedPaths): Array<{
  type: ResourceType;
  resource: ResolvedResource;
}> {
  return RESOURCE_TYPES.flatMap((type) =>
    resolved[type]
      .filter((resource) => resource.metadata.scope === "user")
      .map((resource) => ({ type, resource })),
  );
}

function trimKnownExtension(name: string): string {
  return name.replace(/\.(?:cjs|js|json|jsonc|md|mjs|ts)$/i, "");
}

export function resourceLabel(type: ResourceType, path: string): string {
  if (type === "skills" && basename(path).toLowerCase() === "skill.md") {
    return basename(dirname(path));
  }
  return trimKnownExtension(basename(path, extname(path)));
}

export function sourceLabel(source: string): string {
  if (source === "auto") return "local auto-discovery";
  if (source.startsWith("npm:")) return source.slice(4);
  return source;
}
