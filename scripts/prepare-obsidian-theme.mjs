import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
const require = createRequire(import.meta.url);
const sharp = require('../server/node_modules/sharp');
const manifest = JSON.parse(readFileSync('output/obsidian-archive/generation.json', 'utf8'));
const targets = {
  startup: ['entry/src/main/resources/base/media/theme_startup_obsidian_archive.jpg',841,1870],
  cover_01: ['entry/src/main/resources/base/media/theme_cover_obsidian_archive_01.jpg',450,660],
  cover_02: ['entry/src/main/resources/base/media/theme_cover_obsidian_archive_02.jpg',450,660],
  folder: ['entry/src/main/resources/base/media/theme_folder_art_obsidian_archive.jpg',450,660],
  icon: ['AppScope/resources/base/media/ic_app_theme_obsidian_archive.png',1024,1024]
};
for (const item of manifest.items) {
  if(item.status !== 'success') throw new Error('Image not ready: '+item.key);
  const [file,width,height] = targets[item.key];
  const image = sharp(item.path).resize(width,height,{fit:'cover',position:'centre'});
  if(file.endsWith('.png')) await image.png().toFile(file);
  else await image.jpeg({quality:94,mozjpeg:true}).toFile(file);
  item.sourceSha256=createHash('sha256').update(readFileSync(item.path)).digest('hex');
  item.asset=file;item.assetWidth=width;item.assetHeight=height;
  item.assetSha256=createHash('sha256').update(readFileSync(file)).digest('hex');
  delete item.path;
}
manifest.themeId='obsidian-archive';manifest.themeName='曜金藏书';
manifest.processing='Centre-crop and resize only, JPEG quality 94 / PNG; no regenerated or replaced artwork.';
writeFileSync('scripts/assets/obsidian-theme-generation.json',JSON.stringify(manifest,null,2)+'\n');
console.log('Prepared five Dreamina assets and provenance.');
