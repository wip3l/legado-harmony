import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { ComicColorizer } from '@legado/aiengine';
import { openComicTestContext } from './ComicTestContext';

/** Uses only the explicitly installed fixture and real membership; never changes account entitlement. */
export async function verifyComicWarmup(): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const context: common.Context = await openComicTestContext();
  const fixtureDir = delegator.getAppContext().getApplicationContext().cacheDir;
  if (!ComicColorizer.memberAllowed()) throw new Error('Warmup device verification requires valid membership');
  const source = `${fixtureDir}/comic-color-visual-fixture.jpg`;
  if (!fs.accessSync(source)) throw new Error('Install the explicit comic-color-visual-fixture.jpg first');
  const config = `${fixtureDir}/comic-warmup-mode.txt`;
  const mode = fs.accessSync(config) ? fs.readTextSync(config).trim() : 'smoke';
  const reportPath = `${fixtureDir}/comic-warmup-${mode}.txt`;
  let report = '';
  const log = async (line: string): Promise<void> => {
    report += `${line}\n`;
    const file = fs.openSync(reportPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, report); } finally { fs.closeSync(file); }
    await delegator.print(`[ComicWarmup] ${line}\n`);
  };
  const wait = (ms: number): Promise<void> => new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
  const page = async (label: string, expectCalibration: boolean = false): Promise<void> => {
    let calibrations = 0;
    const progress = (status: string): void => { if (status.includes('校验本机加速')) calibrations++; };
    let result = await ComicColorizer.colorize(context, source, (): boolean => true, progress);
    if (result.cached) {
      fs.unlinkSync(new fileUri.FileUri(result.uri).path);
      result = await ComicColorizer.colorize(context, source, (): boolean => true, progress);
    }
    if (!result.uri || result.cached) throw new Error('Expected an actual uncached page');
    if (result.backend !== 'nnrt') throw new Error(`Expected NNRT on the configured test device: ${result.backend}`);
    if (expectCalibration && calibrations === 0) throw new Error('Expected fresh calibration');
    if (label === 'restart' && calibrations !== 0) throw new Error('Persisted profile did not survive process restart');
    await log(`${label} total=${result.elapsedMs}ms predict=${result.inferenceMs}ms calibration=${calibrations}`);
    fs.copyFileSync(new fileUri.FileUri(result.uri).path, `${fixtureDir}/comic-warmup-result.jpg`);
    fs.unlinkSync(new fileUri.FileUri(result.uri).path);
  };
  ComicColorizer.setAppForeground(true);
  const started = Date.now();
  let testWindow: window.Window | null = null;
  let wasKeepScreenOn = false;
  try {
    await ComicColorizer.prepare(context, (): boolean => true);
    await log(`prepare=${Date.now()-started}ms mode=${mode}`);
    await page(mode === 'restart' ? 'restart' : 'first', mode === 'cold');
    const profiles = `${context.filesDir}/comic_colorizer/backend-profiles.json`;
    if (!fs.accessSync(profiles) || !fs.readTextSync(profiles).includes('nnrt')) throw new Error('Missing persisted calibration');
    if (mode === 'soak') {
      testWindow = await window.getLastWindow(context);
      wasKeepScreenOn = testWindow.getWindowProperties().isKeepScreenOn;
      await testWindow.setWindowKeepScreenOn(true);
      // First waits explicitly cover reading longer than the old 20s lifetime.
      for (const delay of [30000, 60000, 90000]) {
        await wait(delay);
        await page(`retained-${delay / 1000}s`);
      }
      let pass = 0;
      while (Date.now() - started < 30 * 60 * 1000) {
        await wait(30000);
        // Alternating forced release provides a same-build cold-load baseline for the old 20s behavior.
        const cold = pass % 2 === 1;
        if (cold) ComicColorizer.releaseIdleWorker();
        await page(`${cold ? 'released' : 'retained'}-${pass}`);
        pass++;
      }
    } else {
      await page('reused');
      ComicColorizer.releaseIdleWorker();
      await page('worker-recreated');
      ComicColorizer.setAppForeground(false);
      let cancelled = false;
      try { await ComicColorizer.colorize(context, source, (): boolean => true, (): void => {}); }
      catch (error) { cancelled = (error as Error).message === ComicColorizer.CANCELLED; }
      if (!cancelled) throw new Error('Background request was not cancelled');
      ComicColorizer.setAppForeground(true);
      await page('foreground-return');
      ComicColorizer.onMemoryPressure();
      await page('memory-pressure');
    }
    await log(`PASS elapsed=${Date.now()-started}ms`);
  } finally {
    ComicColorizer.releaseIdleWorker();
    if (testWindow) await testWindow.setWindowKeepScreenOn(wasKeepScreenOn);
  }
}
