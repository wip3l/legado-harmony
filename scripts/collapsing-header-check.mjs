// Exercise the actual page callbacks with ArkUI List/Scroll callback arguments.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}.ets`, 'utf8');
const compile = source => stripTypeScriptTypes(source, { mode: 'strip' });
const context = vm.createContext({ SearchBookDetailPage: { TITLE_FADE_DISTANCE: 120 } });
vm.runInContext(compile(read('utils/CollapsingHeader').replace('export class', 'class')), context);

const pages = [
  ['pages/ThemeSettings', 'themeListScroller', true],
  ['pages/SyncDevices', 'headerScroller', true],
  ['pages/SyncIssues', 'headerScroller', true],
  ['pages/LocalBookSettings', 'headerScroller', true],
  ['pages/WebDav', 'headerScroller', true],
  ['pages/OpdsServers', 'headerScroller', true],
  ['pages/ReaderReplaceRules', 'ruleListScroller', true],
  ['pages/CustomTtsVoiceManager', 'voiceListScroller', true],
  ['pages/ExploreSourceSort', 'headerScroller', true],
  ['pages/CoverGalleryManager', 'headerScroller', false],
  ['pages/SearchBookDetail', 'detailScroller', false],
  ['components/common/PageScaffold', 'scroller', false]
];

for (const [file, scrollerName, isList] of pages) {
  const source = read(file);
  const match = source.match(/\.onDidScroll\((\([^\n]*\) => \{[\s\S]*?\n\s*\})\)/);
  assert(match, `${file}: scroll handler exists`);
  let offset = 0;
  const page = {
    headerCollapse: 0,
    detailScrollY: 0,
    collapsible: true,
    [scrollerName]: { currentOffset: () => ({ yOffset: offset }) }
  };
  context.page = page;
  vm.runInContext(compile(`page.onDidScroll = function () { return ${match[1]}; }.call(page);`), context);
  function scroll(delta, state = 1) {
    offset += delta;
    // List: (offset, scrollState); Scroll: (xOffset, yOffset, scrollState).
    if (isList) page.onDidScroll(delta, state);
    else page.onDidScroll(0, delta, state);
  }
  scroll(200);
  assert.equal(page.headerCollapse, 56, `${file}: upward scroll hides header`);
  scroll(-20);
  assert.equal(page.headerCollapse, 36, `${file}: reverse drag starts revealing header away from top`);
  scroll(-40, 2);
  assert.equal(page.headerCollapse, 0, `${file}: downward inertia fully reveals header`);
  scroll(30);
  assert.equal(page.headerCollapse, 30, `${file}: direction can reverse again`);
  scroll(-180);
  assert.equal(page.headerCollapse, 0, `${file}: top overscroll keeps header visible`);
  scroll(10, 2);
  assert.equal(page.headerCollapse, 0, `${file}: spring back to top keeps header visible`);
  if (!isList && file.endsWith('PageScaffold')) {
    page.collapsible = false;
    scroll(100);
    assert.equal(page.headerCollapse, 0, 'non-collapsible scaffold stays visible');
  }
}

// 状态栏遮罩：标题行内容快淡完才显现，完全收起前到位，滚到顶部时消失。
const CollapsingHeader = vm.runInContext('CollapsingHeader', context);
const D = CollapsingHeader.DISTANCE;
assert.equal(CollapsingHeader.scrimOpacity(0), 0, 'scrim hidden while header is expanded');
assert.equal(CollapsingHeader.scrimOpacity(D * 0.3), 0, 'scrim waits for header content to fade');
assert.equal(CollapsingHeader.scrimOpacity(D * 0.9), 1, 'scrim fully shown before header fully collapses');
assert.equal(CollapsingHeader.scrimOpacity(D), 1, 'scrim fully shown when header is collapsed');
assert.equal(CollapsingHeader.scrimOpacity(120, 120), 1, 'custom collapse distance reaches full scrim');
assert.equal(CollapsingHeader.scrimOpacity(10, 0), 0, 'zero distance never shows scrim');
assert(CollapsingHeader.contentOpacity(D * 0.5) < 0.2 && CollapsingHeader.scrimOpacity(D * 0.5) > 0,
  'scrim starts as header content is nearly gone');
for (let c = 1; c <= D; c++) {
  assert(CollapsingHeader.scrimOpacity(c) >= CollapsingHeader.scrimOpacity(c - 1), 'scrim opacity is monotonic');
}

// Run the actual Index callbacks: native animations must not restart on every layout frame.
const indexSource = read('pages/Index');
const indexMethods = indexSource.slice(indexSource.indexOf('  onCurrentIndexChanged(): void {'),
  indexSource.indexOf('  onBookSourceExploreRefreshRequested(): void {'));
const HomeBar = vm.runInNewContext(compile(`class HomeBar { ${indexMethods} }; HomeBar`), {
  HdsAnimationMode: { SCROLL_ANIMATION: 'scroll' }
});
const bar = new HomeBar();
const animations = [];
Object.assign(bar, {
  currentIndex: 0,
  tabHeaderCollapseProgress: [0, 0, 0, 0],
  immersiveTabBarHidden: false,
  supportsImmersiveTabs: () => true,
  immersiveTabsController: {
    applyHideAnimation: mode => animations.push(`hide:${mode}`),
    applyShowAnimation: mode => animations.push(`show:${mode}`),
    setTabBarTranslate: () => assert.fail('native animation owns translation')
  }
});
for (const progress of [0, 0.1, 0.3, 0.5, 0.7, 1, 0.9, 0.5, 0.49, 0.3]) {
  bar.onTabHeaderCollapseChange(0, progress);
}
assert.deepEqual(animations, ['hide:scroll'], 'one hide across continuous scroll and threshold jitter');
bar.onTabHeaderCollapseChange(0, 0.2);
bar.onTabHeaderCollapseChange(0, 0);
assert.deepEqual(animations, ['hide:scroll', 'show:scroll'], 'reverse scroll restores the bar once');
bar.onTabHeaderCollapseChange(1, 1);
bar.onTabHeaderCollapseChange(0, NaN);
assert.equal(animations.length, 2, 'inactive tabs and invalid measurements cannot animate the active bar');
bar.currentIndex = 1;
bar.onCurrentIndexChanged();
assert.equal(animations.at(-1), 'hide:scroll', 'switching to a collapsed retained tab restores its state');
const beforeRemount = animations.length;
bar.syncBottomBarCollapse(true);
assert.equal(animations.length, beforeRemount + 1, 'a recreated HdsTabs receives its hidden state again');
assert.equal(animations.at(-1), 'hide:scroll');
bar.currentIndex = 0;
bar.onCurrentIndexChanged();
assert.equal(animations.at(-1), 'show:scroll', 'a recreated shelf restores the visible bar');

let compatY, compatOpacity;
bar.supportsImmersiveTabs = () => false;
bar.compatTabSafeHeight = () => 24;
bar.compatTabsController = {
  setTabBarTranslate: value => { compatY = value.y; },
  setTabBarOpacity: value => { compatOpacity = value; }
};
const beforeCompat = animations.length;
bar.onTabHeaderCollapseChange(0, 0.5);
assert.equal(compatY, 40, 'older systems keep the continuous slide');
assert.equal(compatOpacity, 0.5, 'older systems keep the continuous fade');
assert.equal(animations.length, beforeCompat, 'older systems never call HDS animations');

console.log(`Collapsing header checks passed for ${pages.length} List/Scroll integrations and native home bar animations.`);
