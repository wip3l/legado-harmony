import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// Usage: node scripts/comic-runtime-report.mjs <benchmark-artifact-directory>
const dir = path.resolve(process.argv[2] || 'output/comic-runtime-20261024');
const read = name => fs.readFileSync(path.join(dir, name), 'utf8').replace(/^\uFEFF/, '');
const variants = ['control-baseline', 'control-optimized', 'control-baseline2', 'control-optimized2'];
const names = ['portrait', 'landscape', 'square', 'tiny'];
const median = values => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const rows = Object.fromEntries(variants.map(name => [name, JSON.parse(read(`${name}.json`))]));
const summary = { runs: {}, combined: {}, images: {} };
for (const variant of variants) {
  const samples = rows[variant];
  if (samples.length !== 25) throw Error(`${variant}: expected all 25 completed samples`);
  summary.runs[variant] = {};
  for (const name of names) {
    const warm = samples.filter(row => row.name === name && row.pass > 0);
    if (warm.length !== 5) throw Error(`${variant}/${name}: missing warm samples`);
    summary.runs[variant][name] = {
      samples: warm.length, medianMs: median(warm.map(row => row.totalMs)),
      predictMedianMs: median(warm.map(row => row.predictMs)),
      overheadMedianMs: median(warm.map(row => row.totalMs - row.predictMs)),
      coldMs: samples.find(row => row.name === name && row.pass === 0).totalMs,
      backends: [...new Set(warm.map(row => row.backend))]
    };
  }
}
for (const name of names) {
  const collect = variants => variants.flatMap(v => rows[v].filter(r => r.name === name && r.pass > 0));
  const before = collect(['control-baseline', 'control-baseline2']);
  const after = collect(['control-optimized', 'control-optimized2']);
  const beforeMs = median(before.map(r => r.totalMs));
  const afterMs = median(after.map(r => r.totalMs));
  summary.combined[name] = {samplesPerVariant: before.length, beforeMs, afterMs,
    reductionPercent: Number(((1 - afterMs / beforeMs) * 100).toFixed(1))};
}
for (const name of [...names, 'square-return']) {
  const hashes = Object.fromEntries(variants.map(variant => [variant,
    crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, `${variant}-${name}.jpg`))).digest('hex')]));
  summary.images[name] = { byteIdentical: new Set(Object.values(hashes)).size === 1, hashes };
  if (!summary.images[name].byteIdentical) throw Error(`Output changed: ${name}`);
}
fs.writeFileSync(path.join(dir, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
console.log(JSON.stringify(summary.combined, null, 2));
console.log('All 20 saved JPEG outputs match their corresponding baseline byte for byte.');
