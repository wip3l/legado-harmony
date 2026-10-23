// Resize/crop only; never substitutes artwork or generates variants from other themes.
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
const require=createRequire(import.meta.url);
const sharp=require('../server/node_modules/sharp');
const state=JSON.parse(fs.readFileSync('output/neon-harbor/generation.json','utf8'));
const media='entry/src/main/resources/base/media/';
const targets={
  startup:[media+'theme_startup_neon_harbor.jpg',841,1870],
  folder:[media+'theme_folder_art_neon_harbor.jpg',450,660],
  icon:['AppScope/resources/base/media/ic_app_theme_neon_harbor.png',1024,1024],
  tts_light:[media+'tts_panel_neon_harbor_light.jpg',720,520],
  tts_dark:[media+'tts_panel_neon_harbor_dark.jpg',720,520],
  ...Object.fromEntries(Array.from({length:6},(_,i)=>[`cover_0${i+1}`,[media+`theme_cover_neon_harbor_0${i+1}.jpg`,450,660]]))
};
const hash=file=>createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const manifest={themeId:state.themeId,themeName:state.themeName,provider:state.provider,model:state.model,resolution:state.resolution,
  processing:'Centre crop and resize only. JPEG quality 94; PNG for launcher. Original reference used for three portraits.',
  failedAttempts:(state.failedAttempts||[]).map(x=>({key:x.key,submitId:x.submit_id,status:x.gen_status,reason:x.fail_reason,prompt:x.prompt,reportedCredits:x.credit_count})),items:[]};
for(const [key,[asset,width,height]] of Object.entries(targets)) {
  const item=state.items.find(x=>x.key===key);
  if(item?.gen_status!=='success'||!item.path)throw new Error(`Artwork not ready: ${key}`);
  const metadata=await sharp(item.path).metadata();
  const resized=sharp(item.path).resize(width,height,{fit:'cover',position:'centre'});
  await (asset.endsWith('.png')?resized.png():resized.jpeg({quality:94,mozjpeg:true})).toFile(asset);
  manifest.items.push({key,submitId:item.submit_id,status:item.gen_status,prompt:item.prompt,
    ...(item.promptIsSummary?{promptIsSummary:true}:{}),
    ...(item.reference?{referenceSubmitId:state.items.find(x=>x.key==='startup').submit_id}:{}),
    reportedCredits:item.credit_count,sourceWidth:metadata.width,sourceHeight:metadata.height,sourceSha256:hash(item.path),
    asset,width,height,assetSha256:hash(asset)});
}
fs.writeFileSync('docs/neon-harbor-generation.json',JSON.stringify(manifest,null,2)+'\n');
// Contact sheet for inspection of every delivered bitmap.
const tiles=[];
for(const [index,item] of manifest.items.entries()) {
  const x=(index%6)*270,y=Math.floor(index/6)*425;
  tiles.push({input:await sharp(item.asset).resize(250,370,{fit:'contain',background:'#182032'}).png().toBuffer(),left:x+10,top:y+10});
  const label=Buffer.from(`<svg width="270" height="35"><text x="12" y="23" fill="#F5EADF" font-family="sans-serif" font-size="17">${item.key}</text></svg>`);
  tiles.push({input:label,left:x,top:y+385});
}
await sharp({create:{width:1620,height:850,channels:3,background:'#131A2C'}}).composite(tiles).png().toFile('output/neon-harbor/contact-sheet.png');
console.log('Prepared 11 Dreamina images, provenance and contact sheet.');
