import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule as read } from './lib/ets-module-staging.mjs';

const end = Date.parse('2026-11-11T00:00:00+08:00');
const features = ['super-resolution', 'colorization', 'translation'];
const withoutImports = source => source.replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, '');

function fixture({ now = end - 10000, persisted = new Map() } = {}) {
  const clock = { now, uptime: 1000 };
  const values = new Map(), timers = new Map();
  let timerId = 0;
  const sandbox = vm.createContext({
    Date: class extends Date { static now() { return clock.now; } },
    systemDateTime: { TimeType: { STARTUP: 0 }, getUptime: () => clock.uptime },
    preferences: { getPreferences: async () => ({ put: async () => {}, delete: async () => {}, flush: async () => {} }) },
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => {
      values.set(key, value);
      if (persisted.has(key)) persisted.set(key, value);
    } },
    PersistentStorage: { persistProp: (key, fallback) => {
      if (!persisted.has(key)) persisted.set(key, fallback);
      values.set(key, persisted.get(key));
    } },
    setTimeout: (fn, delay) => { const id = ++timerId; timers.set(id, { fn, delay }); return id; },
    clearTimeout: id => timers.delete(id),
    deviceInfo: { sdkApiVersion: 26 }, canIUse: () => true,
    ComicTextRecognizer: { supported: () => true }
  });
  for (const file of ['account/AccountCommerceModels.ets', 'account/AccountSessionStore.ets',
    'account/AiAccessPolicy.ets', 'runtime/AiRuntime.ets', 'utils/AppAiHost.ets',
    'core/reader/ReaderComicComputeQueue.ts', 'core/reader/ReaderComicSuperResolution.ets',
    'core/reader/ComicColorizer.ets', 'core/reader/ComicChineseConverter.ets']) {
    vm.runInContext(stripTypeScriptTypes(withoutImports(read(file))), sandbox);
  }
  const api = vm.runInContext(`({ policy: AiAccessPolicy, session: AccountSessionStore, runtime: AiRuntime,
    sr: ReaderComicSuperResolution, color: ComicColorizer, translation: ComicChineseConverter })`, sandbox);
  vm.runInContext('AppAiHost.install(); AiAccessPolicy.initialize();', sandbox);
  const login = async ({ member = false, serverNow = clock.now, ...extra } = {}) => api.session.saveLogin({}, {
    sessionToken: 'token', account: { userId: 'reader', memberVerifiedAt: clock.now,
      membership: { active: member, restricted: false, serverNow,
        state: member ? { sku: 'MONTHLY', expiresAt: end + 100000 } : null }, ...extra }
  });
  const advance = ms => { clock.now += ms; clock.uptime += ms; };
  return { ...api, sandbox, clock, values, timers, persisted, login, advance };
}

test('only logged-in users get the three AI features before the Beijing trial deadline', async () => {
  const f = fixture();
  f.policy.start();
  assert.equal(f.policy.ENDS_AT, Date.parse('2026-11-10T16:00:00Z'));
  for (const feature of features) assert.equal(f.runtime.isAllowed(feature), false);
  assert.equal(f.policy.actionText(), '登录后免费试用');
  await f.login();
  for (const feature of features) assert.equal(f.runtime.isAllowed(feature), true);
  assert.equal(f.session.activeMembershipSku(), '', 'trial must not grant membership');
  assert.equal(f.session.hasMemberThemeAccess('paid-theme'), false);
  assert.equal(f.runtime.isAllowed('cloud-tts'), false);
  assert.equal(f.runtime.isAllowed('future-ai'), false);
  assert.equal(f.sr.access(), 'ready');
  assert.equal(f.color.memberAllowed(), true);
  assert.equal(f.translation.access(), 'ready');
  f.sandbox.deviceInfo.sdkApiVersion = 25;
  assert.equal(f.sr.access(), 'unsupported', 'trial does not bypass device capabilities');
  f.sandbox.ComicTextRecognizer.supported = () => false;
  assert.equal(f.translation.access(), 'unsupported');
  await f.session.clear({});
  for (const feature of features) assert.equal(f.runtime.isAllowed(feature), false);
  await assert.rejects(f.color.colorize({}, 'image', () => true, () => {}), /会员专享/);
  await f.login();
  for (const feature of features) assert.equal(f.runtime.isAllowed(feature), true);
});

test('extended trial reopens after the old deadline even when the previous campaign was closed', async () => {
  const f = fixture({ now: Date.parse('2026-11-01T00:00:00+08:00'),
    persisted: new Map([['aiLaunchTrial20261101Ended', true]]) });
  f.policy.start();
  for (const feature of features) assert.equal(f.runtime.isAllowed(feature), false);
  await f.login();
  for (const feature of features) assert.equal(f.runtime.isAllowed(feature), true);
  assert.equal(f.values.get('aiTrialOpen'), true);
  assert.match(f.policy.TRIAL_LABEL, /11 月 10 日/);
});

test('exact expiry refreshes open pages, persists closure and preserves paid access', async () => {
  const f = fixture({ now: end - 1 });
  await f.login();
  f.policy.start();
  assert.equal(f.values.get('aiTrialOpen'), true);
  const timer = [...f.timers.values()][0];
  assert.equal(timer.delay, 1);
  assert.equal(f.runtime.isAllowed('translation'), true);
  f.advance(1);
  for (const feature of features) assert.equal(f.runtime.isAllowed(feature), false);
  timer.fn();
  assert.equal(f.values.get('aiTrialOpen'), false);
  assert.equal(f.timers.size, 0);
  assert.match(f.policy.blockedMessage(), /试用已结束/);
  await f.login({ member: true });
  for (const feature of features) assert.equal(f.runtime.isAllowed(feature), true);
  assert.equal(f.runtime.isAllowed('future-ai'), false);
  await f.session.clear({});
  for (const feature of features) assert.equal(f.runtime.isAllowed(feature), false);
  const restarted = fixture({ now: end - 86400000, persisted: f.persisted });
  await restarted.login();
  restarted.policy.start();
  assert.equal(restarted.runtime.isAllowed('translation'), false, 'rollback/restart must not reopen confirmed expiry');
});

test('server time takes precedence and uptime advances through wall-clock rollback and background', async () => {
  const f = fixture({ now: end - 86400000 });
  await f.login({ serverNow: end - 1000 });
  f.policy.start();
  assert.equal(f.runtime.isAllowed('colorization'), true);
  f.clock.now -= 86400000;
  f.clock.uptime += 1000;
  assert.equal(f.runtime.isAllowed('colorization'), false);
  f.policy.refresh();
  assert.equal(f.values.get('aiTrialOpen'), false);

  const background = fixture({ now: end - 100 });
  await background.login();
  background.policy.start();
  background.policy.stop();
  assert.equal(background.timers.size, 0);
  background.advance(101);
  background.policy.start();
  assert.equal(background.values.get('aiTrialOpen'), false);
  assert.equal(background.runtime.isAllowed('super-resolution'), false);

  const ahead = fixture({ now: end + 86400000 });
  await ahead.login({ serverNow: end - 1000 });
  ahead.policy.start();
  assert.equal(ahead.runtime.isAllowed('translation'), true, 'use available server time over an incorrect device date');
});

test('without a server clock use device time; expired members can trial, but no grants remain after deadline', async () => {
  const f = fixture();
  await f.login({ membership: null });
  f.policy.start();
  assert.equal(f.runtime.isAllowed('translation'), true);
  f.advance(10000);
  assert.equal(f.runtime.isAllowed('translation'), false);
  f.policy.refresh();
  assert.equal(f.values.get('aiTrialOpen'), false);
});

test('single-page conversion discards a late dictionary result after logout and clears an existing preview', async () => {
  const f = fixture();
  await f.login();
  f.policy.start();
  let resolveDictionary;
  f.translation.load = () => new Promise(resolve => { resolveDictionary = resolve; });
  f.sandbox.getContext = () => ({});
  f.sandbox.HdsFeedback = { showToast: () => {} };
  let source = withoutImports(read('pages/ComicText.ets'));
  source = source.slice(0, source.indexOf('  build()')) + '}';
  source = source.replace(/@Entry|@Component/g, '').replace('struct ComicTextPage', 'class ComicTextPage')
    .replace(/@(?:State|Prop)\s+|@(?:StorageProp|StorageLink|Watch)\('[^']+'\)\s+/g, '');
  vm.runInContext(stripTypeScriptTypes(source), f.sandbox);
  const page = vm.runInContext('new ComicTextPage()', f.sandbox);
  page.visible = true;
  page.original = '繁體';
  const pending = page.simplify();
  await f.session.clear({});
  resolveDictionary({ convert: () => '繁体' });
  await pending;
  assert.equal(page.showSimplified, false);
  assert.equal(page.simplified, '');
  assert.equal(page.converting, false);
  page.simplified = '繁体';
  page.showSimplified = true;
  page.refreshAccess();
  assert.equal(page.showSimplified, false);
  assert.equal(page.simplified, '');
  assert.equal(page.original, '繁體', 'plain OCR remains available');
});
