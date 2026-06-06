import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class CoverGallerySnapshot {
  albumsRaw: string = '';
  lightAlbumId: string = '';
  darkAlbumId: string = '';
  applyScope: string = 'all';
  targetBooksRaw: string = '';
  ignoreSourceCover: boolean = false;
  coverMode: string = 'sequence';
}

export class CoverGalleryStore {
  private static readonly STORE_NAME: string = 'cover_gallery_settings';
  private static readonly KEY_ALBUMS: string = 'bookshelfCoverAlbums';
  private static readonly KEY_LIGHT_ALBUM: string = 'bookshelfLightCoverAlbumId';
  private static readonly KEY_DARK_ALBUM: string = 'bookshelfDarkCoverAlbumId';
  private static readonly KEY_APPLY_SCOPE: string = 'bookshelfCoverApplyScope';
  private static readonly KEY_TARGET_BOOKS: string = 'bookshelfCoverTargetBooks';
  private static readonly KEY_IGNORE_SOURCE: string = 'bookshelfIgnoreSourceCover';
  private static readonly KEY_COVER_MODE: string = 'bookshelfCoverMode';
  private static cachedSnapshot: CoverGallerySnapshot | null = null;

  static async saveFromStorage(context: Context): Promise<void> {
    const snapshot = CoverGalleryStore.snapshotFromStorage();
    if (!CoverGalleryStore.hasAlbumPayload(snapshot.albumsRaw)) {
      const preferenceSnapshot = await CoverGalleryStore.loadFromPreferences(context);
      if (CoverGalleryStore.hasAlbumPayload(preferenceSnapshot.albumsRaw)) {
        await CoverGalleryStore.save(context, preferenceSnapshot);
        return;
      }
    }
    await CoverGalleryStore.save(context, snapshot);
  }

  static async save(context: Context, snapshot: CoverGallerySnapshot): Promise<void> {
    CoverGalleryStore.cachedSnapshot = CoverGalleryStore.cloneSnapshot(snapshot);
    const store = await preferences.getPreferences(context, CoverGalleryStore.STORE_NAME);
    await store.put(CoverGalleryStore.KEY_ALBUMS, snapshot.albumsRaw);
    await store.put(CoverGalleryStore.KEY_LIGHT_ALBUM, snapshot.lightAlbumId);
    await store.put(CoverGalleryStore.KEY_DARK_ALBUM, snapshot.darkAlbumId);
    await store.put(CoverGalleryStore.KEY_APPLY_SCOPE, snapshot.applyScope);
    await store.put(CoverGalleryStore.KEY_TARGET_BOOKS, snapshot.targetBooksRaw);
    await store.put(CoverGalleryStore.KEY_IGNORE_SOURCE, snapshot.ignoreSourceCover);
    await store.put(CoverGalleryStore.KEY_COVER_MODE, snapshot.coverMode);
    await store.flush();
  }

  static async load(context: Context): Promise<CoverGallerySnapshot> {
    if (CoverGalleryStore.cachedSnapshot) {
      return CoverGalleryStore.cloneSnapshot(CoverGalleryStore.cachedSnapshot);
    }

    const storageSnapshot = CoverGalleryStore.snapshotFromStorage();
    const preferenceSnapshot = await CoverGalleryStore.loadFromPreferences(context);

    if (CoverGalleryStore.hasAlbumPayload(preferenceSnapshot.albumsRaw)) {
      return preferenceSnapshot;
    }

    if (CoverGalleryStore.hasAlbumPayload(storageSnapshot.albumsRaw)) {
      await CoverGalleryStore.save(context, storageSnapshot);
      return storageSnapshot;
    }

    return preferenceSnapshot;
  }

  static applyToStorage(snapshot: CoverGallerySnapshot): void {
    CoverGalleryStore.cachedSnapshot = CoverGalleryStore.cloneSnapshot(snapshot);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_ALBUMS, snapshot.albumsRaw);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_LIGHT_ALBUM, snapshot.lightAlbumId);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_DARK_ALBUM, snapshot.darkAlbumId);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_APPLY_SCOPE, snapshot.applyScope);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_TARGET_BOOKS, snapshot.targetBooksRaw);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_IGNORE_SOURCE, snapshot.ignoreSourceCover);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_COVER_MODE, snapshot.coverMode);
  }

  private static async getString(store: preferences.Preferences, key: string, fallback: string): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static async getBoolean(store: preferences.Preferences, key: string, fallback: boolean): Promise<boolean> {
    const value = await store.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  private static snapshotFromStorage(): CoverGallerySnapshot {
    const snapshot = new CoverGallerySnapshot();
    snapshot.albumsRaw = AppStorage.get<string>(CoverGalleryStore.KEY_ALBUMS) || '';
    snapshot.lightAlbumId = AppStorage.get<string>(CoverGalleryStore.KEY_LIGHT_ALBUM) || '';
    snapshot.darkAlbumId = AppStorage.get<string>(CoverGalleryStore.KEY_DARK_ALBUM) || '';
    snapshot.applyScope = AppStorage.get<string>(CoverGalleryStore.KEY_APPLY_SCOPE) || 'all';
    snapshot.targetBooksRaw = AppStorage.get<string>(CoverGalleryStore.KEY_TARGET_BOOKS) || '';
    snapshot.ignoreSourceCover = AppStorage.get<boolean>(CoverGalleryStore.KEY_IGNORE_SOURCE) || false;
    snapshot.coverMode = AppStorage.get<string>(CoverGalleryStore.KEY_COVER_MODE) || 'sequence';
    return snapshot;
  }

  private static async loadFromPreferences(context: Context): Promise<CoverGallerySnapshot> {
    const store = await preferences.getPreferences(context, CoverGalleryStore.STORE_NAME);
    const snapshot = new CoverGallerySnapshot();
    snapshot.albumsRaw = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_ALBUMS, '');
    snapshot.lightAlbumId = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_LIGHT_ALBUM, '');
    snapshot.darkAlbumId = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_DARK_ALBUM, '');
    snapshot.applyScope = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_APPLY_SCOPE, 'all');
    snapshot.targetBooksRaw = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_TARGET_BOOKS, '');
    snapshot.ignoreSourceCover = await CoverGalleryStore.getBoolean(store, CoverGalleryStore.KEY_IGNORE_SOURCE, false);
    snapshot.coverMode = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_COVER_MODE, 'sequence');
    return snapshot;
  }

  private static hasAlbumPayload(raw: string): boolean {
    return (raw || '').trim().length > 0;
  }

  private static cloneSnapshot(source: CoverGallerySnapshot): CoverGallerySnapshot {
    const snapshot = new CoverGallerySnapshot();
    snapshot.albumsRaw = source.albumsRaw;
    snapshot.lightAlbumId = source.lightAlbumId;
    snapshot.darkAlbumId = source.darkAlbumId;
    snapshot.applyScope = source.applyScope;
    snapshot.targetBooksRaw = source.targetBooksRaw;
    snapshot.ignoreSourceCover = source.ignoreSourceCover;
    snapshot.coverMode = source.coverMode;
    return snapshot;
  }
}
