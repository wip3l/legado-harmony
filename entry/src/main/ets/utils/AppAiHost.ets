import { worker } from '@kit.ArkTS';
import { AiHost, AiRuntime } from '@legado/aiengine';
import { digestHashHex } from '@legado/sourceengine';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { ReaderCacheBudget } from '../core/book/ReaderCacheBudget';
import { ReaderComicImageExport } from '../core/reader/ReaderComicImageExport';
import { ReaderImageMarker } from '../core/book/ReaderImageMarker';
import { ReaderImageResults } from '../core/book/ReaderImageResults';

/** The app retains membership, network/image source and cache policy. */
export class AppAiHost implements AiHost {
  static install(): void { AiRuntime.install(new AppAiHost()); }
  isAllowed(_feature: string): boolean { return AccountSessionStore.activeMembershipSku() !== ''; }
  cacheDir(): string { return AppStorage.get<string>('appCacheDir') || ''; }
  downloadImage(source: string): Promise<Uint8Array> { return ReaderComicImageExport.downloadImage(source); }
  digestHashHex(algorithm: string, value: string): string { return digestHashHex(algorithm, value); }
  touchComicFile(path: string): void { ReaderCacheBudget.touchComicFile(path); }
  noteComicWrite(): void { ReaderCacheBudget.noteComicWrite(); }
  resolveImageSource(marker: string): string {
    const value = ReaderImageMarker.parse(marker).source;
    const pending = ReaderImageMarker.pendingRaw(value);
    const source = pending ? ReaderImageResults.current(pending) : value;
    return ReaderImageMarker.failureReason(source) ? '' : source;
  }
  createColorWorker(): worker.ThreadWorker {
    return new worker.ThreadWorker('../workers/ComicColorWorker.ets', { name: 'ComicColor' });
  }
}
