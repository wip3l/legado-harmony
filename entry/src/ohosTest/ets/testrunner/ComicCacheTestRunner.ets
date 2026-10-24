import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { ComicColorizer, ComicColorResult, ReaderComicComputeQueue } from '@legado/aiengine';
import { openComicTestContext } from './ComicTestContext';

class CacheSample {
  name: string = '';
  elapsedMs: number = 0;
  reads: number = 0;
  cached: boolean = false;
  whileBusy: boolean = false;
}

/** Real production APIs and an explicit fixture; never reads books or alters entitlement. */
export default class ComicCacheTestRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    let view: window.Window | null = null;
    let keep = false;
    let message = 'PASS ComicCache';
    let code = 0;
    try {
      const context = await openComicTestContext();
      view = await window.getLastWindow(context);
      keep = view.getWindowProperties().isKeepScreenOn;
      await view.setWindowKeepScreenOn(true);
      await this.verify(context);
    } catch (error) { message = `FAIL ComicCache: ${(error as Error).message}`; code = -1; }
    finally {
      ComicColorizer.releaseIdleWorker();
      if (view) await view.setWindowKeepScreenOn(keep);
    }
    await delegator.finishTest(message, code);
  }

  private write(path: string, bytes: ArrayBuffer | string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
  }

  private async verify(context: common.Context): Promise<void> {
    if (!ComicColorizer.memberAllowed()) throw new Error('Requires real membership');
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const args = abilityDelegatorRegistry.getArguments().parameters;
    const label = args['-s cacheLabel'] || args['cacheLabel'] || 'optimized';
    const expectFast = (args['-s cacheFast'] || args['cacheFast']) === 'true';
    if (!/^[a-z0-9-]+$/.test(label)) throw new Error('Invalid label');
    const dir = delegator.getAppContext().getApplicationContext().cacheDir;
    const original = fs.openSync(`${dir}/comic-color-visual-fixture.jpg`, fs.OpenMode.READ_ONLY);
    let fixture: Uint8Array;
    try {
      const data = new ArrayBuffer(fs.statSync(original.fd).size);
      let offset = 0;
      while (offset < data.byteLength) {
        const part = new ArrayBuffer(data.byteLength - offset);
        const count = fs.readSync(original.fd, part, { length: part.byteLength });
        if (count <= 0) throw new Error('Incomplete fixture');
        new Uint8Array(data).set(new Uint8Array(part, 0, count), offset); offset += count;
      }
      fixture = new Uint8Array(data);
    } finally { fs.closeSync(original); }
    if (fixture[0] !== 255 || fixture[1] !== 216) throw new Error('Expected JPEG fixture');
    // A JPEG comment changes content identity without changing pixels, geometry or file size.
    const a = new Uint8Array(fixture.length + 5);
    a.set(fixture.subarray(0, 2)); a.set(new Uint8Array([255, 254, 0, 3, 65]), 2); a.set(fixture.subarray(2), 7);
    const b = new Uint8Array(a); b[6] = 66;
    const source = `${dir}/comic-cache-${label}-source.jpg`;
    const other = `${dir}/comic-cache-${label}-other.jpg`;
    const swap = `${dir}/comic-cache-${label}-swap.jpg`;
    const samples: CacheSample[] = [];
    const persist = (): void => this.write(`${dir}/comic-cache-${label}.json`, JSON.stringify(samples));
    const measure = async (name: string, path: string, busy: () => boolean = (): boolean => false): Promise<ComicColorResult> => {
      const row = new CacheSample(); row.name = name;
      const started = Date.now();
      const result = await ComicColorizer.colorize(context, path, (): boolean => true, (status: string): void => {
        if (status === '正在读取原图…') row.reads++;
      });
      row.elapsedMs = Date.now() - started; row.cached = result.cached; row.whileBusy = busy();
      samples.push(row); persist();
      await delegator.print(`[ComicCache] ${label} ${JSON.stringify(row)}\n`);
      return result;
    };
    try {
      this.write(source, a.buffer as ArrayBuffer); this.write(other, b.buffer as ArrayBuffer);
      const first = await measure('seed', source);
      for (let i = 0; i < 10; i++) {
        const result = await measure(`idle-${i}`, i % 2 ? fileUri.getUriFromPath(source) : source);
        if (!result.cached || result.uri !== first.uri || (expectFast && samples[samples.length - 1].reads !== 0))
          throw new Error('Unchanged local hit re-read source or returned wrong output');
      }

      let release: () => void = (): void => {};
      let entered: () => void = (): void => {};
      const enteredGate = new Promise<void>((resolve: () => void): void => { entered = resolve; });
      let occupied = true;
      const gate = ReaderComicComputeQueue.run(async (): Promise<void> => {
        await new Promise<void>((resolve: () => void): void => { release = resolve; entered(); }); occupied = false;
      });
      await enteredGate;
      const timer = setTimeout((): void => release(), 1000);
      try {
        await measure('queue-held-1000ms', source, (): boolean => occupied);
        if (expectFast && !samples[samples.length - 1].whileBusy) throw new Error('Cache hit waited for native queue');
      } finally { clearTimeout(timer); release(); await gate; }

      // Remove only this comment-tagged test output if a previous run already populated it.
      const seedOther = await measure('seed-other', other);
      fs.unlinkSync(new fileUri.FileUri(seedOther.uri).path);
      let nativeEntered: () => void = (): void => {};
      const startedNative = new Promise<void>((resolve: () => void): void => { nativeEntered = resolve; });
      let computing = true;
      const native = ComicColorizer.colorize(context, other, (): boolean => true, (status: string): void => {
        if (status === '正在本机着色…') nativeEntered();
      }).then((result: ComicColorResult): ComicColorResult => { computing = false; nativeEntered(); return result; },
        (error: Error): ComicColorResult => { computing = false; nativeEntered(); throw error; });
      await startedNative;
      try {
        await measure('during-real-inference', source, (): boolean => computing);
        if (expectFast && !samples[samples.length - 1].whileBusy) throw new Error('Cached page blocked behind actual inference');
      } finally { await native; }

      // Both hashes now exist: perform same-size writes and checks within one wall-clock second.
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 1010 - Date.now() % 1000); });
      this.write(source, a.buffer as ArrayBuffer);
      await measure('before-rewrite', source);
      const rewriteStart = Date.now();
      this.write(source, b.buffer as ArrayBuffer);
      const rewritten = await measure('same-size-rewrite', source);
      if (rewritten.uri !== seedOther.uri || rewritten.uri === first.uri) throw new Error('Stale result after same-size write');
      if (samples[samples.length - 1].reads !== 1) throw new Error('Changed content was not hashed');
      // Set the exact same millisecond mtime on both versions, leaving ctime as the change signal.
      const oldMtime = Date.now() - 60000;
      fs.utimes(source, oldMtime);
      await measure('fixed-mtime-seed', source);
      this.write(source, a.buffer as ArrayBuffer); fs.utimes(source, oldMtime);
      if ((await measure('restored-mtime', source)).uri !== first.uri) throw new Error('Stale result with restored mtime');
      await delegator.print(`[ComicCache] rewriteChecks=${Date.now()-rewriteStart}ms\n`);
      this.write(swap, b.buffer as ArrayBuffer); fs.renameSync(swap, source);
      if ((await measure('atomic-replace', source)).uri !== seedOther.uri) throw new Error('Stale result after replacement');
      fs.unlinkSync(source);
      let rejected = false;
      try { await measure('deleted-source', source); } catch (_) { rejected = true; }
      if (!rejected) throw new Error('Deleted source returned a cached image');
      this.write(source, a.buffer as ArrayBuffer); await measure('restored-source', source);
      fs.unlinkSync(new fileUri.FileUri(first.uri).path);
      if ((await measure('evicted-output', source)).cached) throw new Error('Evicted JPEG was returned');
      if (!(await measure('after-rebuild', source)).cached) throw new Error('Rebuilt result not cached');
      fs.copyFileSync(new fileUri.FileUri(first.uri).path, `${dir}/comic-cache-${label}-result.jpg`);
      persist();
    } finally {
      for (const path of [source, other, swap]) { try { fs.unlinkSync(path); } catch (_) {} }
    }
  }
}
