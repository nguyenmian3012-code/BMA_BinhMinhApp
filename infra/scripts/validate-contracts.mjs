import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const root = new URL('../../contracts/', import.meta.url);
const schemas = new URL('schemas/', root);
const examples = new URL('examples/', root);

for (const name of await readdir(schemas)) {
  if (name.endsWith('.json')) JSON.parse(await readFile(new URL(name, schemas), 'utf8'));
}

for (const name of await readdir(examples)) {
  if (!name.endsWith('.json')) continue;
  const event = JSON.parse(await readFile(new URL(name, examples), 'utf8'));
  const hash = createHash('sha256').update(JSON.stringify(event.payload)).digest('hex');
  if (event.payload_hash !== hash) throw new Error(`${name}: payload_hash mismatch`);
  if (event.schema_version !== '1.0') throw new Error(`${name}: unsupported schema`);
}

process.stdout.write('Contracts and example hashes are valid.\n');
