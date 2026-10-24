import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { HttpClient } from '@legado/sourceengine';
import { ReaderImageScheduler } from '../core/book/ReaderImageScheduler';

/** Device/network-specific preference: persisted locally, not synced to other devices. */
export class NetworkSettingsStore {
  static readonly KEY: string = 'networkForceHttp1';
  static readonly IMAGE_KEY: string = 'readerImageConcurrency';
  private static readonly STORE: string = 'network_settings';
  private static revision: number = 0;
  private static imageRevision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const revision = NetworkSettingsStore.revision;
    const imageRevision = NetworkSettingsStore.imageRevision;
    const store = await preferences.getPreferences(context, NetworkSettingsStore.STORE);
    const value = await store.get(NetworkSettingsStore.KEY, false);
    if (revision === NetworkSettingsStore.revision) NetworkSettingsStore.apply(value === true);
    const concurrency = await store.get(NetworkSettingsStore.IMAGE_KEY, ReaderImageScheduler.DEFAULT_CONCURRENCY);
    if (imageRevision === NetworkSettingsStore.imageRevision) {
      NetworkSettingsStore.applyImageConcurrency(typeof concurrency === 'number' ? concurrency : 4);
    }
  }

  static save(context: Context, value: boolean): Promise<void> {
    ++NetworkSettingsStore.revision;
    const write = NetworkSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, NetworkSettingsStore.STORE);
      await store.put(NetworkSettingsStore.KEY, value);
      await store.flush();
      NetworkSettingsStore.apply(value);
    });
    NetworkSettingsStore.writes = write.catch(() => {});
    return write;
  }

  private static apply(value: boolean): void {
    HttpClient.forceHttp1 = value;
    AppStorage.setOrCreate(NetworkSettingsStore.KEY, value);
  }

  static saveImageConcurrency(context: Context, value: number): Promise<void> {
    ++NetworkSettingsStore.imageRevision;
    const next = ReaderImageScheduler.normalizeConcurrency(value);
    const write = NetworkSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, NetworkSettingsStore.STORE);
      await store.put(NetworkSettingsStore.IMAGE_KEY, next);
      await store.flush();
      NetworkSettingsStore.applyImageConcurrency(next);
    });
    NetworkSettingsStore.writes = write.catch(() => {});
    return write;
  }

  private static applyImageConcurrency(value: number): void {
    ReaderImageScheduler.setConcurrency(value);
    AppStorage.setOrCreate(NetworkSettingsStore.IMAGE_KEY, ReaderImageScheduler.concurrency);
  }
}
