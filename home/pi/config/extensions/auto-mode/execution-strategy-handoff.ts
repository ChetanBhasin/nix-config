/** Migration surface for the separate execution-strategy extension.
 * Deliberately NOT registered/imported by Auto Mode. The strategy owner decides
 * when to enable this independently of unattended availability.
 */
export function promoteOwnerLaunchToAsync(input: Record<string, unknown>, policy: { enabled: boolean; owner: boolean }): void {
  const launch = input.action === undefined && (typeof input.agent === "string" || typeof input.workflowScript === "string");
  if (policy.enabled && policy.owner && launch && !Object.hasOwn(input, "async") && input.foregroundOnly !== true) input.async = true;
}

export const DELEGATION_GUIDANCE = `Delegate useful independent or context-heavy work when it helps; keep small deterministic tasks local. Inspect executable roles before assignment and give each child a bounded goal, scope, authority, evidence, validation and output artifact contract. Use fresh context unless inherited history is necessary. Choose concurrency from actual dependencies and capacity, not a lane quota. Consume artifacts at dependency barriers, without polling or duplicative prompts. Writer leases and protected-action boundaries apply regardless of strategy.`;
