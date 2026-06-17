import { font, UIContext } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import graphicsText from '@ohos.graphics.text';

export class ReaderFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

export class ReaderFontRegisterResult {
  familyName: string = '';
  filePath: string = '';
  registered: boolean = false;
  arkUiRegistered: boolean = false;
  legacyRegistered: boolean = false;
  graphicsTextRegistered: boolean = false;
  arkUiSource: string = '';
  legacySource: string = '';
  graphicsTextSource: string = '';
  errorSummary: string = '';
}

class ReaderGraphicsFontRecord {
  familyName: string = '';
  filePath: string = '';
}

export class ReaderFontHelper {
  private static registeredGraphicsFonts: ReaderGraphicsFontRecord[] = [];
  private static readonly ACTIVE_READER_FONT_FAMILY: string = 'ReaderCustomFontActive';

  static normalizeFontFamily(filePath: string): string {
    return ReaderFontHelper.stableFontFamily(filePath);
  }

  static stableFontFamily(filePath: string): string {
    const seed = ReaderFontHelper.fileNameFromPath(filePath);
    let hash = 0;
    for (let i = 0; i < filePath.length; i++) {
      hash = ((hash * 31) + filePath.charCodeAt(i)) & 0x7fffffff;
    }
    return `ReaderCustomFont_${ReaderFontHelper.sanitizeFontToken(seed)}_${hash}`;
  }

  static runtimeFontFamily(filePath: string): string {
    return ReaderFontHelper.ACTIVE_READER_FONT_FAMILY;
  }

  static registerFont(uiContext: UIContext | null, item: ReaderFontItem): ReaderFontRegisterResult {
    const result = new ReaderFontRegisterResult();
    if (!item || !item.filePath || !ReaderFontHelper.fontFileExists(item.filePath)) {
      return result;
    }
    const preparedPath = ReaderFontHelper.ensureAsciiFontPath(item.filePath);
    result.filePath = preparedPath;
    result.familyName = ReaderFontHelper.runtimeFontFamily(preparedPath);
    const errors: string[] = [];

    const sources = ReaderFontHelper.fontSources(preparedPath);
    for (const familySrc of sources) {
      if (uiContext) {
        try {
          uiContext.getFont().registerFont({
            familyName: result.familyName,
            familySrc: familySrc
          });
          result.arkUiRegistered = true;
          result.arkUiSource = familySrc;
          console.info(`当前 UIContext 注册阅读字体成功: ${result.familyName}, ${familySrc}`);
          break;
        } catch (e) {
          errors.push(`UIContext ${familySrc}: ${JSON.stringify(e)}`);
          console.warn(`当前 UIContext 注册阅读字体失败: ${familySrc}`, e);
        }
      }
    }

    for (const familySrc of sources) {
      try {
        font.registerFont({
          familyName: result.familyName,
          familySrc: familySrc
        });
        result.legacyRegistered = true;
        result.legacySource = familySrc;
        console.info(`全局注册阅读字体成功: ${result.familyName}, ${familySrc}`);
        break;
      } catch (e) {
        errors.push(`legacy ${familySrc}: ${JSON.stringify(e)}`);
        console.warn(`全局注册阅读字体失败: ${familySrc}`, e);
      }
    }
    result.graphicsTextRegistered = ReaderFontHelper.registerGraphicsTextFont(result.familyName, preparedPath, result);
    result.registered = result.arkUiRegistered;
    result.errorSummary = errors.join(' | ');
    return result;
  }

  static registerGraphicsTextFont(
    familyName: string,
    filePath: string,
    result?: ReaderFontRegisterResult
  ): boolean {
    if (ReaderFontHelper.hasRegisteredGraphicsFamily(familyName, filePath)) {
      return true;
    }
    ReaderFontHelper.unloadGraphicsFamily(familyName);
    for (const familySrc of ReaderFontHelper.fontSources(filePath)) {
      if (!familySrc.startsWith('file://')) {
        continue;
      }
      try {
        graphicsText.FontCollection.getGlobalInstance().loadFontSyncWithCheck(familyName, familySrc);
        ReaderFontHelper.rememberGraphicsFamily(familyName, filePath);
        if (result) {
          result.graphicsTextSource = familySrc;
        }
        console.info(`graphics.text 注册阅读字体成功: ${familyName}, ${familySrc}`);
        return true;
      } catch (e) {
        try {
          graphicsText.FontCollection.getGlobalInstance().loadFontSync(familyName, familySrc);
          ReaderFontHelper.rememberGraphicsFamily(familyName, filePath);
          if (result) {
            result.graphicsTextSource = familySrc;
          }
          console.info(`graphics.text 注册阅读字体成功: ${familyName}, ${familySrc}`);
          return true;
        } catch (err) {
          console.warn(`graphics.text 注册阅读字体失败: ${familySrc}`, err);
        }
      }
    }
    return false;
  }

  static hasRegisteredGraphicsFamily(familyName: string, filePath: string): boolean {
    for (const item of ReaderFontHelper.registeredGraphicsFonts) {
      if (item.familyName === familyName && item.filePath === filePath) {
        return true;
      }
    }
    return false;
  }

  static rememberGraphicsFamily(familyName: string, filePath: string): void {
    const next: ReaderGraphicsFontRecord[] = [];
    for (const item of ReaderFontHelper.registeredGraphicsFonts) {
      if (item.familyName !== familyName) {
        next.push(item);
      }
    }
    const record = new ReaderGraphicsFontRecord();
    record.familyName = familyName;
    record.filePath = filePath;
    next.push(record);
    ReaderFontHelper.registeredGraphicsFonts = next;
  }

  static unloadGraphicsFamily(familyName: string): void {
    try {
      graphicsText.FontCollection.getGlobalInstance().unloadFontSync(familyName);
    } catch (e) {
    }
    const next: ReaderGraphicsFontRecord[] = [];
    for (const item of ReaderFontHelper.registeredGraphicsFonts) {
      if (item.familyName !== familyName) {
        next.push(item);
      }
    }
    ReaderFontHelper.registeredGraphicsFonts = next;
  }

  static fontSources(filePath: string): string[] {
    const result: string[] = [];
    ReaderFontHelper.pushUnique(result, `file://${filePath}`);
    ReaderFontHelper.pushUnique(result, filePath);
    try {
      ReaderFontHelper.pushUnique(result, fileUri.getUriFromPath(filePath));
    } catch (e) {
      console.warn('生成阅读字体 file uri 失败:', e);
    }
    return result;
  }

  static pushUnique(result: string[], value: string): void {
    if (!value) {
      return;
    }
    for (const item of result) {
      if (item === value) {
        return;
      }
    }
    result.push(value);
  }

  static fontFileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  static ensureAsciiFontPath(filePath: string): string {
    const name = ReaderFontHelper.fileNameFromPath(filePath);
    if (ReaderFontHelper.isAsciiSafeFileName(name) || !ReaderFontHelper.fontFileExists(filePath)) {
      return filePath;
    }
    const dirIndex = Math.max(filePath.lastIndexOf('/'), filePath.lastIndexOf('\\'));
    if (dirIndex < 0) {
      return filePath;
    }
    const dir = filePath.substring(0, dirIndex);
    let targetPath = `${dir}/${ReaderFontHelper.asciiStoredFontName(name, 0)}`;
    let index = 1;
    while (ReaderFontHelper.fontFileExists(targetPath)) {
      targetPath = `${dir}/${ReaderFontHelper.asciiStoredFontName(name, index)}`;
      index++;
    }
    try {
      fs.renameSync(filePath, targetPath);
      return targetPath;
    } catch (e) {
      console.warn('迁移阅读字体文件名失败:', e);
      return filePath;
    }
  }

  static fileNameFromPath(path: string): string {
    const decoded = decodeURIComponent(path || '');
    const index = Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\'));
    return index >= 0 ? decoded.substring(index + 1) : decoded || 'font';
  }

  static fontExt(uri: string): string {
    const lower = (uri || '').toLowerCase();
    if (lower.includes('.otf')) return '.otf';
    if (lower.includes('.ttc')) return '.ttc';
    return '.ttf';
  }

  static asciiStoredFontName(sourceName: string, salt: number): string {
    const ext = ReaderFontHelper.fontExt(sourceName);
    let hash = salt & 0x7fffffff;
    for (let i = 0; i < sourceName.length; i++) {
      hash = ((hash * 31) + sourceName.charCodeAt(i)) & 0x7fffffff;
    }
    return `reader_font_${hash}${ext}`;
  }

  static isAsciiSafeFileName(name: string): boolean {
    if (!name || name.includes('/') || name.includes('\\')) {
      return false;
    }
    for (let i = 0; i < name.length; i++) {
      const code = name.charCodeAt(i);
      if (code < 33 || code > 126) {
        return false;
      }
    }
    return true;
  }

  static sanitizeFontToken(value: string): string {
    let token = '';
    for (let i = 0; i < value.length; i++) {
      const ch = value.charAt(i);
      const code = value.charCodeAt(i);
      const isDigit = code >= 48 && code <= 57;
      const isUpper = code >= 65 && code <= 90;
      const isLower = code >= 97 && code <= 122;
      token += (isDigit || isUpper || isLower) ? ch : '_';
    }
    while (token.includes('__')) {
      token = token.replace('__', '_');
    }
    token = token.replace(/^_+|_+$/g, '');
    return token || 'font';
  }
}
