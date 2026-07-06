import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class TtsSettings {
  person: number = 0;
  online: number = 1;
  style: string = '';
  language: string = 'zh-CN';
  speed: number = 1;
  installedVoiceKeys: string = '';
  customVoiceId: string = '';
  customVoices: string = '';
}

export class TtsSettingsStore {
  static readonly KEY_PERSON: string = 'ttsPerson';
  static readonly KEY_ONLINE: string = 'ttsOnline';
  static readonly KEY_STYLE: string = 'ttsStyle';
  static readonly KEY_LANGUAGE: string = 'ttsLanguage';
  static readonly KEY_SPEED: string = 'ttsSpeed';
  static readonly KEY_INSTALLED_VOICE_KEYS: string = 'ttsInstalledVoiceKeys';
  static readonly KEY_CUSTOM_VOICE_ID: string = 'ttsCustomVoiceId';
  static readonly KEY_CUSTOM_VOICES: string = 'ttsCustomVoices';
  private static readonly STORE_NAME: string = 'tts_settings';
  private static cachedSettings: TtsSettings | null = null;

  static async load(context: Context): Promise<TtsSettings> {
    if (TtsSettingsStore.cachedSettings) {
      return TtsSettingsStore.clone(TtsSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, TtsSettingsStore.STORE_NAME);
    const settings = new TtsSettings();
    const storageSettings = TtsSettingsStore.fromStorage();
    settings.person = await TtsSettingsStore.getNumber(
      store, TtsSettingsStore.KEY_PERSON, storageSettings.person, 'person');
    settings.online = await TtsSettingsStore.getNumber(
      store, TtsSettingsStore.KEY_ONLINE, storageSettings.online, 'online');
    settings.style = await TtsSettingsStore.getString(store, TtsSettingsStore.KEY_STYLE, storageSettings.style);
    settings.language = await TtsSettingsStore.getString(
      store, TtsSettingsStore.KEY_LANGUAGE, storageSettings.language);
    settings.speed = await TtsSettingsStore.getNumber(
      store, TtsSettingsStore.KEY_SPEED, storageSettings.speed, 'speed');
    settings.installedVoiceKeys = await TtsSettingsStore.getString(
      store, TtsSettingsStore.KEY_INSTALLED_VOICE_KEYS, storageSettings.installedVoiceKeys);
    settings.customVoiceId = await TtsSettingsStore.getString(
      store, TtsSettingsStore.KEY_CUSTOM_VOICE_ID, storageSettings.customVoiceId);
    settings.customVoices = await TtsSettingsStore.getString(
      store, TtsSettingsStore.KEY_CUSTOM_VOICES, storageSettings.customVoices);
    TtsSettingsStore.cachedSettings = TtsSettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: TtsSettings): Promise<void> {
    const normalized = TtsSettingsStore.clone(settings);
    TtsSettingsStore.cachedSettings = TtsSettingsStore.clone(normalized);
    TtsSettingsStore.applyToStorage(normalized);
    const store = await preferences.getPreferences(context, TtsSettingsStore.STORE_NAME);
    await store.put(TtsSettingsStore.KEY_PERSON, normalized.person);
    await store.put(TtsSettingsStore.KEY_ONLINE, normalized.online);
    await store.put(TtsSettingsStore.KEY_STYLE, normalized.style);
    await store.put(TtsSettingsStore.KEY_LANGUAGE, normalized.language);
    await store.put(TtsSettingsStore.KEY_SPEED, normalized.speed);
    await store.put(TtsSettingsStore.KEY_INSTALLED_VOICE_KEYS, normalized.installedVoiceKeys);
    await store.put(TtsSettingsStore.KEY_CUSTOM_VOICE_ID, normalized.customVoiceId);
    await store.put(TtsSettingsStore.KEY_CUSTOM_VOICES, normalized.customVoices);
    await store.flush();
  }

  static applyToStorage(settings: TtsSettings): void {
    const normalized = TtsSettingsStore.clone(settings);
    TtsSettingsStore.cachedSettings = TtsSettingsStore.clone(normalized);
    AppStorage.setOrCreate(TtsSettingsStore.KEY_PERSON, normalized.person);
    AppStorage.setOrCreate(TtsSettingsStore.KEY_ONLINE, normalized.online);
    AppStorage.setOrCreate(TtsSettingsStore.KEY_STYLE, normalized.style);
    AppStorage.setOrCreate(TtsSettingsStore.KEY_LANGUAGE, normalized.language);
    AppStorage.setOrCreate(TtsSettingsStore.KEY_SPEED, normalized.speed);
    AppStorage.setOrCreate(TtsSettingsStore.KEY_INSTALLED_VOICE_KEYS, normalized.installedVoiceKeys);
    AppStorage.setOrCreate(TtsSettingsStore.KEY_CUSTOM_VOICE_ID, normalized.customVoiceId);
    AppStorage.setOrCreate(TtsSettingsStore.KEY_CUSTOM_VOICES, normalized.customVoices);
  }

  static fromStorage(): TtsSettings {
    const settings = new TtsSettings();
    settings.person = AppStorage.get<number>(TtsSettingsStore.KEY_PERSON) ?? 0;
    settings.online = AppStorage.get<number>(TtsSettingsStore.KEY_ONLINE) ?? 1;
    settings.style = AppStorage.get<string>(TtsSettingsStore.KEY_STYLE) || '';
    settings.language = AppStorage.get<string>(TtsSettingsStore.KEY_LANGUAGE) || 'zh-CN';
    settings.speed = AppStorage.get<number>(TtsSettingsStore.KEY_SPEED) ?? 1;
    settings.installedVoiceKeys = AppStorage.get<string>(TtsSettingsStore.KEY_INSTALLED_VOICE_KEYS) || '';
    settings.customVoiceId = AppStorage.get<string>(TtsSettingsStore.KEY_CUSTOM_VOICE_ID) || '';
    settings.customVoices = AppStorage.get<string>(TtsSettingsStore.KEY_CUSTOM_VOICES) || '';
    return TtsSettingsStore.clone(settings);
  }

  private static async getNumber(
    store: preferences.Preferences,
    key: string,
    fallback: number,
    type: string
  ): Promise<number> {
    const value = await store.get(key, fallback);
    if (typeof value === 'number') {
      return TtsSettingsStore.normalizeNumber(value, type, fallback);
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      if (!Number.isNaN(parsed)) {
        return TtsSettingsStore.normalizeNumber(parsed, type, fallback);
      }
    }
    return fallback;
  }

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    if (typeof value === 'string') {
      return value;
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value);
    }
    return fallback;
  }

  private static normalizeNumber(value: number, type: string, fallback: number): number {
    if (type === 'person') {
      return Math.max(0, Math.round(value));
    }
    if (type === 'online') {
      return Math.round(value) === 0 ? 0 : 1;
    }
    if (type === 'speed') {
      return Math.max(0.5, Math.min(2, Math.round(value * 10) / 10));
    }
    return fallback;
  }

  private static normalizeLanguage(language: string): string {
    const value = (language || 'zh-CN').trim().replace(/_/g, '-').toLowerCase();
    if (value === 'zh' || value === 'zh-cn' || value.startsWith('zh-hans')) {
      return 'zh-CN';
    }
    if (value === 'en' || value === 'en-us') {
      return 'en-US';
    }
    return value || 'zh-CN';
  }

  private static clone(source: TtsSettings): TtsSettings {
    const settings = new TtsSettings();
    settings.person = TtsSettingsStore.normalizeNumber(source.person, 'person', 0);
    settings.online = TtsSettingsStore.normalizeNumber(source.online, 'online', 1);
    settings.style = source.style || '';
    settings.language = TtsSettingsStore.normalizeLanguage(source.language || 'zh-CN');
    settings.speed = TtsSettingsStore.normalizeNumber(source.speed, 'speed', 1);
    settings.installedVoiceKeys = source.installedVoiceKeys || '';
    settings.customVoiceId = source.customVoiceId || '';
    settings.customVoices = source.customVoices || '';
    return settings;
  }
}
