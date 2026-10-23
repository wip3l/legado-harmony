// Dreamina originals -> six production covers. No painted replacement of generated artwork.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const sharp = require('../server/node_modules/sharp');
const source = 'output/obsidian-archive-v2/generation.json';
const state = JSON.parse(readFileSync(source, 'utf8'));
if (state.items.length !== 6 || state.items.some(item => item.status !== 'success' || !item.path)) {
  throw new Error('All six Dreamina covers must be downloaded successfully before installation.');
}
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const items = [];
for (const item of state.items) {
  const asset = `entry/src/main/resources/base/media/theme_cover_obsidian_archive_${item.key}.jpg`;
  await sharp(item.path).resize(450, 660, { fit: 'cover', position: 'centre' })
    .jpeg({ quality: 94, mozjpeg: true }).toFile(asset);
  const { path: originalPath, ...record } = item;
  items.push({ ...record, sourceSha256: hash(readFileSync(originalPath)), asset,
    assetWidth: 450, assetHeight: 660, assetSha256: hash(readFileSync(asset)) });
}
writeFileSync('scripts/assets/obsidian-theme-cover-refresh.json', JSON.stringify({
  tool: state.tool, session: state.session, model: state.model, resolution: state.resolution,
  themeId: 'obsidian-archive', revision: 2,
  processing: 'Centre crop and resize to 450x660; JPEG quality 94. Replaces covers 01/02 and adds 03–06.',
  items
}, null, 2) + '\n');
console.log('Prepared six Dreamina covers and revision provenance.');
