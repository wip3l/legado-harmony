import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { createHash } from 'node:crypto';
import { loadObsidianReader } from './lib/obsidian-reader-fixture.mjs';
// Reuse the production reader harness, including theme application and native text styles.
const {ThemeRuntime:runtime,ThemeAssetRegistry:assets,BuiltinThemeRegistry:registry,
  ReaderHarness,ReaderCommentBubblePainter:painter,store,sandbox,Canvas}=loadObsidianReader();
const pack=registry.findById('neon-harbor');
assert.equal(pack.id,'neon-harbor');
assert.equal(registry.all().filter(p=>p.id==='neon-harbor').length,1);
assert.notEqual(pack.light,pack.dark);
const luminance=color=>{
  const rgb=[1,3,5].map(i=>parseInt(color.slice(i,i+2),16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);
  return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;
};
const contrast=(a,b)=>{const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);};
const metrics=[];
runtime.applyTheme(pack.id);
const reader=new ReaderHarness();
for(const dark of [false,true]) {
  store.set('appDarkMode',dark);reader.appDarkMode=dark;
  const variant=dark?pack.dark:pack.light,mode=dark?'dark':'light';
  for(const bg of [variant.colors.pageColor,variant.colors.cardColor]) {
    for(const fg of [variant.colors.primaryTextColor,variant.colors.subTextColor,variant.colors.accentColor]) {
      assert(contrast(bg,fg)>=4.5,`UI contrast ${mode}: ${bg}/${fg}`);
    }
  }
  for(const bg of [variant.colors.buttonColor,variant.colors.accentColor,variant.colors.dangerColor]) {
    assert(contrast(bg,runtime.onAccentColor(bg))>=4.5,`Button contrast ${mode}`);
  }
  const body=contrast(variant.reader.backgroundColor,variant.reader.textColor);
  assert(body>=7,`Reading contrast ${mode}`);
  assert(contrast(variant.reader.backgroundColor,variant.reader.subTextColor)>=4.5);
  metrics.push(`${mode} reader ${body.toFixed(2)}:1`);
  const id=variant.reader.backgroundAssetId;
  assert.equal(assets.normalizeBackgroundAssetId(id),id);
  assert.equal(assets.readerBackgroundDecoration(id),`app.media.reader_decor_neon_harbor_${mode}`);
  assert.equal(assets.readerBackgroundTrailingDecoration(id),`app.media.reader_decor_neon_harbor_trailing_${mode}`);
  assert.equal(assets.readerBackgroundTrailingRotation(id),0);
  assert.equal(runtime.regexBubbleStyle(),'harbor-postcard');
  const native=reader.buildReaderV2RegexStyleTemplate({});
  assert.equal(native.decorationStyleId,'harbor-postcard');
  assert(native.backgroundEnabled && native.decorationEnabled);
  assert.equal(native.backgroundColor,dark?0xFF3B3048:0xFFEEDBD7);
  assert.equal(native.color,dark?0xFFFFE5D5:0xFF643244);
  assert(contrast(variant.regexEmphasis.emphasisColor,variant.regexEmphasis.emphasisTextColor)>=7);
  const comment=reader.readerCommentBubbleStyle();
  assert.equal(comment.ornament,'postcard');
  const hex=x=>'#'+(x>>>0).toString(16).slice(2);
  assert(contrast(hex(comment.fill),hex(comment.text))>=4.5);
  for(const label of ['1','128','999+','本章说']) {
    const canvas=new Canvas(),h=painter.heightFor(18),w=Math.max(h,label.length*18+18*.84);
    painter.paint(canvas,10,10,10+w,10+h,comment,true);
    assert.equal(canvas.commands.length,4);
    assert(canvas.commands.every(c=>!c.d.includes('NaN')));
  }
  store.set(dark?runtime.KEY_DARK_REGEX_BUBBLE_STYLE:runtime.KEY_LIGHT_REGEX_BUBBLE_STYLE,'invalid');
  assert.equal(runtime.regexBubbleStyle(),'harbor-postcard');
  runtime.applyTheme(pack.id);
}
assert.equal(assets.normalizeIconPackId(pack.navigation.iconPackId),'neon-harbor');
for(const tab of ['bookshelf','explore','search','mine'])assert.equal(assets.navigationIcon('neon-harbor',tab),`app.media.ic_theme_neon_harbor_${tab}`);
assert.equal(assets.startupBackground(pack.startup.styleId),'app.media.theme_startup_neon_harbor');
assert.equal(assets.themeShelfFolder(pack.book.shelfFolderAssetId),'app.media.theme_folder_art_neon_harbor');
assert.equal(new Set(assets.themeBookCovers(pack.book.coverAssetId)).size,6);
// Standard theme ownership and current-trial appearance must follow the existing policy.
runtime.applyTheme('plain-default');store.set('appThemeId','plain-default');
assert.equal(vm.runInContext("ThemeAccessPolicy.canUseBubbleStyle('harbor-postcard')",sandbox),false);
store.set('appThemeId','neon-harbor');
assert.equal(vm.runInContext("ThemeAccessPolicy.canUseBubbleStyle('harbor-postcard')",sandbox),true);
const manifest=JSON.parse(fs.readFileSync('scripts/assets/neon-harbor-generation.json','utf8'));
assert.equal(manifest.items.length,11);
for(const item of manifest.items) {
  assert.equal(item.status,'success');
  assert.equal(createHash('sha256').update(fs.readFileSync(item.asset)).digest('hex'),item.assetSha256);
}
console.log('PASS: Neon Harbor registration, real reader/native bubble pipeline, comment drawing, asset routing, entitlement fallback and provenance. '+metrics.join('; '));
