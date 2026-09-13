import { createHash } from 'node:crypto';
import { lstatSync, readFileSync, readdirSync, realpathSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';

export function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map(k => `${JSON.stringify(k)}:${stable(value[k])}`).join(',')}}`;
  return JSON.stringify(value);
}
export const digest = value => createHash('sha256').update(stable(value)).digest('hex');
export function check(ok, message) { if (!ok) throw new Error(message); }
export const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export function text(value, label) {
  check(typeof value === 'string' && value.trim().length > 0 && value.length <= 12000, `${label}: nonempty bounded text required`);
  return value;
}
export function id(value) { check(typeof value === 'string' && /^[A-Za-z][A-Za-z0-9._-]{0,99}$/.test(value), 'safe stable ID required'); return value; }
export function unique(values, label) { check(Array.isArray(values) && new Set(values).size === values.length, `${label}: array without duplicates required`); return values; }
export function pathKey(value) {
  text(value, 'scope');
  check(isAbsolute(value), 'scopes must be absolute paths, not globs');
  check(!/[\x00*?\[\]{}]/.test(value), 'scope cannot contain glob/control syntax');
  const absolute = resolve(value);
  let parent = absolute;
  const tail = [];
  while (true) {
    try { return resolve(realpathSync(parent), ...tail.reverse()); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      check(dirname(parent) !== parent, `cannot resolve scope ${value}`);
      tail.push(relative(dirname(parent), parent)); parent = dirname(parent);
    }
  }
}
export const contains = (a, b) => a === b || b.startsWith(a.endsWith(sep) ? a : `${a}${sep}`);
export const overlap = (a, b) => contains(a, b) || contains(b, a);
export const intersects = (a, b) => a.some(x => b.some(y => overlap(x, y)));
export const scopes = values => unique(values, 'scopes').map(pathKey);

/** No gitignore exclusions: omitted, unreadable, symlinked or oversized trees must not look reviewed. */
export function hashScope(path) {
  const rows = []; let bytes = 0;
  function visit(file) {
    let info;
    try { info = lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') { rows.push([file, 'missing']); return; } throw error; }
    check(!info.isSymbolicLink(), `symlink in scope: ${file}; declare real scopes explicitly`);
    check(rows.length < 20000 && bytes < 64 * 1024 * 1024, 'scope hashing limit; narrow scopes (never a partial hash)');
    if (info.isDirectory()) {
      rows.push([file, 'directory']);
      for (const name of readdirSync(file).sort()) visit(join(file, name));
    } else {
      check(info.isFile(), `unsupported scope file: ${file}`);
      bytes += info.size;
      check(bytes <= 64 * 1024 * 1024, 'scope hashing byte limit; narrow scopes');
      rows.push([file, info.mode, createHash('sha256').update(readFileSync(file)).digest('hex')]);
    }
  }
  visit(path); return digest(rows);
}
export const hashPaths = paths => Object.fromEntries(paths.map(path => [path, hashScope(path)]));
