import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const sharp = require('../server/node_modules/sharp');
const state = JSON.parse(readFileSync('output/obsidian-archive-v2/folder/generation.json', 'utf8'));
if (state.status !== 'success' || !state.path) throw new Error('Folder artwork has not completed.');
const asset = 'entry/src/main/resources/base/media/theme_folder_art_obsidian_archive.jpg';
await sharp(state.path).resize(450, 660, { fit: 'cover', position: 'centre' })
  .jpeg({ quality: 94, mozjpeg: true }).toFile(asset);
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const { path, ...record } = state;
writeFileSync('scripts/assets/obsidian-theme-folder-refresh.json', JSON.stringify({
  ...record, themeId: 'obsidian-archive', revision: 2, sourceSha256: hash(path),
  asset, assetWidth: 450, assetHeight: 660, assetSha256: hash(asset),
  processing: 'Centre crop and resize only; JPEG quality 94. Supersedes the original folder artwork.'
}, null, 2) + '\n');
console.log('Prepared Dreamina folder artwork and provenance.');
