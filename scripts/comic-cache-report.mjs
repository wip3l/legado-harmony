import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const dir = path.resolve(process.argv[2] || 'output/comic-cache-20261024');
const variants = ['baseline', 'optimized', 'baseline2', 'optimized2'];
const median = numbers => {
  const values = [...numbers].sort((a, b) => a - b), middle = Math.floor(values.length / 2);
  return values.length % 2 ? values[middle] : (values[middle - 1] + values[middle]) / 2;
};
const runs = {};
const hashes = {};
for (const variant of variants) {
  const rows = JSON.parse(fs.readFileSync(path.join(dir, `${variant}.json`), 'utf8').replace(/^\uFEFF/, ''));
  const idle = rows.filter(row => /^idle-\d+$/.test(row.name));
  const fast = variant.startsWith('optimized');
  assert.equal(idle.length, 10);
  assert.ok(idle.every(row => row.cached && row.reads === (fast ? 0 : 1)));
  const held = rows.find(row => row.name === 'queue-held-1000ms');
  const native = rows.find(row => row.name === 'during-real-inference');
  for (const row of [held, native]) {
    assert.ok(row.cached); assert.equal(row.whileBusy, fast); assert.equal(row.reads, fast ? 0 : 1);
  }
  assert.equal(rows.find(row => row.name === 'evicted-output').cached, false);
  for (const name of ['same-size-rewrite', 'restored-mtime', 'atomic-replace']) {
    assert.equal(rows.find(row => row.name === name).reads, 1);
  }
  assert.match(fs.readFileSync(path.join(dir, `${variant}-run.log`), 'utf8'), /TestFinished-ResultMsg: PASS ComicCache/);
  runs[variant] = { idleSamples: idle.map(row => row.elapsedMs), idleMedianMs: median(idle.map(row => row.elapsedMs)),
    queueHeldMs: held.elapsedMs, duringNativeMs: native.elapsedMs, bypassedBusyQueue: fast };
  hashes[variant] = crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, `${variant}-result.jpg`))).digest('hex');
}
assert.equal(new Set(Object.values(hashes)).size, 1, 'baseline and optimized JPEG outputs differ');
const result = { runs, combined: {
  beforeIdleMs: median([...runs.baseline.idleSamples, ...runs.baseline2.idleSamples]),
  afterIdleMs: median([...runs.optimized.idleSamples, ...runs.optimized2.idleSamples]),
  samplesPerVariant: 20, clockResolutionMs: 1
}, byteIdentical: true, hashes };
fs.writeFileSync(path.join(dir, 'summary.json'), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify(result, null, 2));
