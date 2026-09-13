import { Type } from 'typebox';
import { StringEnum } from '@earendil-works/pi-ai';

const string = Type.String({ minLength: 1, maxLength: 12000 });
const strings = Type.Array(string);
const input = Type.Object({ id: string, kind: StringEnum(['dependency', 'contract', 'assumption']), paths: strings, value: string }, { additionalProperties: false });
const obligation = Type.Object({ id: string, kind: StringEnum(['requirement', 'risk']), description: string, scopes: strings, inputs: strings, dependsOn: strings }, { additionalProperties: false });
const lane = Type.Object({ id: string, role: StringEnum(['discovery', 'writer', 'reviewer', 'integration']), owner: StringEnum(['parent', 'child']), agent: Type.Optional(string), access: StringEnum(['read', 'write']), goal: string, constraints: strings, scopes: strings, dependsOn: strings, obligations: strings, inputs: strings }, { additionalProperties: false });
export const strategySchema = Type.Object({
  action: StringEnum(['status', 'plan', 'extend', 'prepare', 'cancel', 'consume', 'parent', 'input', 'gate']),
  plan: Type.Optional(Type.Object({ workflow: string, goal: string, inputs: Type.Array(input), obligations: Type.Array(obligation), lanes: Type.Array(lane) }, { additionalProperties: false })),
  lane: Type.Optional(string), attempt: Type.Optional(string), input: Type.Optional(string), value: Type.Optional(string),
  conclusion: Type.Optional(string), evidence: Type.Optional(strings),
  async: Type.Optional(Type.Boolean()), foregroundOnly: Type.Optional(Type.Boolean()),
}, { additionalProperties: false });
