import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

class FontProbeInfo {
  fullName?: string;
  familyName?: string;
  postScriptName?: string;
}

export class ReaderSystemFontHelper {
  static readonly FALLBACK_SYSTEM_FONT_FAMILY: string = 'sans-serif';

  static resolve(uiContext: UIContext | null): string {
    const probed = ReaderSystemFontHelper.probeUiContextFont(uiContext);
    return probed || ReaderSystemFontHelper.FALLBACK_SYSTEM_FONT_FAMILY;
  }

  static applyToStorage(uiContext: UIContext | null): string {
    const family = ReaderSystemFontHelper.resolve(uiContext);
    AppStorage.setOrCreate<string>('readerSystemFontFamily', family);
    return family;
  }

  static currentFromStorage(uiContext?: UIContext | null): string {
    const stored = AppStorage.get<string>('readerSystemFontFamily') || '';
    if (stored) {
      return stored;
    }
    return ReaderSystemFontHelper.applyToStorage(uiContext ?? null);
  }

  private static probeUiContextFont(uiContext: UIContext | null): string {
    if (!uiContext) {
      return '';
    }
    try {
      const info = uiContext.getFont().getFontByName('') as FontProbeInfo | null;
      return ReaderSystemFontHelper.normalizeProbeInfo(info);
    } catch (err) {
      hilog.warn(0x0000, 'testTag', 'Probe system font failed: %{public}s', JSON.stringify(err));
      return '';
    }
  }

  private static normalizeProbeInfo(info: FontProbeInfo | null): string {
    if (!info) {
      return '';
    }
    return info.familyName || info.fullName || info.postScriptName || '';
  }
}
