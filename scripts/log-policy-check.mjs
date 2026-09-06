import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const scan = ['entry/src/main/ets/core', 'entry/src/main/ets/utils', 'entry/src/main/ets/pages'];
const files = scan.flatMap((p) => {
  const walk = (dir) => fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap((e) => {
    const rel = path.join(dir, e.name);
    return e.isDirectory() ? walk(rel) : /\.(ets|ts)$/.test(e.name) ? [rel] : [];
  });
  return walk(p);
});
const violations = [];
for (const rel of files) {
  const lines = fs.readFileSync(path.join(root, rel), 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    if (/console\.log\s*\(/.test(line) && /(URL|url|Cookie|cookie|token|password|secret)/i.test(line)) {
      violations.push(`${rel}:${i + 1}`);
    }
  });
}
if (violations.length) {
  console.error(`Log policy check failed (${violations.length} potentially sensitive logs):\n${violations.join('\n')}`);
  process.exit(1);
}
console.log('Log policy check passed.');
