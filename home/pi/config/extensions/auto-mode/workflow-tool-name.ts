const PROVIDER_NAMESPACE = "functions.";
const BASE_NAME = /^[A-Za-z0-9_-]+$/;

/** Canonicalize only Pi's known provider wire namespace; arbitrary namespaces stay distinct. */
export function canonicalToolName(value: string): string {
  if (!value.startsWith(PROVIDER_NAMESPACE)) return value;
  const base = value.slice(PROVIDER_NAMESPACE.length);
  return BASE_NAME.test(base) ? base : value;
}

export function sameToolName(left: string, right: string): boolean {
  return canonicalToolName(left) === canonicalToolName(right);
}

export function hasActiveTool(active: Iterable<string>, required: string): boolean {
  const expected = canonicalToolName(required);
  for (const tool of active) if (canonicalToolName(tool) === expected) return true;
  return false;
}
