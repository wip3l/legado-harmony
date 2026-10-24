import { common } from '@kit.AbilityKit';
import image from '@ohos.multimedia.image';
import { router } from '@kit.ArkUI';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { ReaderImageMarker } from '../book/ReaderImageMarker';
import { ReaderImageResults } from '../book/ReaderImageResults';
import { ReaderComicImageExport, ReaderComicSnapshotProvider } from './ReaderComicImageExport';
import { ComicTextRequests } from './ComicTextRequests';

/** 阅读页为漫画图片操作提供的环境。 */
export interface ReaderComicImageActionsHost {
  uiContext: () => UIContext;
  abilityContext: () => common.UIAbilityContext;
  accentColor: () => string;
  /** Return true when the reader handled in-place coloring; otherwise use the standalone page. */
  colorPage?: (source: string) => boolean;
  /** 本地导入的书：图片不会过期，不自动刷新。 */
  isLocalBook: () => boolean;
  currentChapter: () => number;
  /** 正在加载或正在切章，此时不刷新，等这一章成为当前章再处理。 */
  busy: () => boolean;
  /** 重新抓取当前章并停在当前页，不弹“本章已刷新”。 */
  refreshCurrentChapter: () => void;
}

/**
 * 漫画图片操作：长按菜单（保存到相册、分享、重新加载）与图片地址过期后的自动刷新。
 * 图片被服务器拒绝（401/403）多是正文缓存里的签名地址过期：重新抓取本章换新地址。
 * 每章只自动刷新一次，免得书源本身拒绝时反复刷新；相邻章节等它成为当前章再刷新。
 */
export class ReaderComicImageActions {
  private readonly host: ReaderComicImageActionsHost;
  /** 图片被拒、等成为当前章时再刷新的章节。 */
  private deniedChapters: Set<number> = new Set();
  /** 本次打开已自动刷新过的章节。 */
  private refreshedChapters: Set<number> = new Set();

  constructor(host: ReaderComicImageActionsHost) {
    this.host = host;
  }

  reset(): void {
    this.deniedChapters.clear();
    this.refreshedChapters.clear();
  }

  async showMenu(markerSource: string, reload: () => void, snapshotId: string): Promise<void> {
    let source = markerSource;
    const pendingRaw = ReaderImageMarker.pendingRaw(source);
    if (pendingRaw) {
      // 渐进加载的图片按处理结果操作；还没处理好时没有可保存的内容。
      source = ReaderImageResults.current(pendingRaw);
      if (!source) {
        HdsFeedback.showToast('图片还在加载');
        return;
      }
    }
    if (!source) return;
    const failure = ReaderImageMarker.failureReason(source);
    if (failure) {
      // 获取正文时就没拿到这张图，没有可保存的内容；只能重新抓取本章。
      try {
        await this.host.uiContext().getPromptAction().showActionMenu({
          title: failure.length > 60 ? `${failure.substring(0, 60)}…` : failure,
          buttons: [{ text: '刷新本章', color: this.host.accentColor() }]
        });
      } catch (_) {
        return;
      }
      if (!this.host.busy()) this.host.refreshCurrentChapter();
      return;
    }
    const snapshot: ReaderComicSnapshotProvider | null = snapshotId ?
      (): Promise<image.PixelMap> => this.host.uiContext().getComponentSnapshot().get(snapshotId) : null;
    let index = -1;
    try {
      const color = this.host.accentColor();
      const result = await this.host.uiContext().getPromptAction().showActionMenu({
        title: '图片',
        buttons: [
          { text: '保存到相册', color: color },
          { text: '分享', color: color },
          { text: '重新加载', color: color },
          { text: '查看本页文字', color: color },
          { text: '本页着色（会员）', color: color }
        ]
      });
      index = result.index;
    } catch (_) {
      // 点空白处取消。
      return;
    }
    if (index === 2) {
      reload();
      return;
    }
    if (index === 3 || index === 4) {
      if (index === 4 && this.host.colorPage?.(source)) return;
      const requestId = ComicTextRequests.put(source);
      try {
        await router.pushUrl({ url: index === 4 ? 'pages/ComicColor' : 'pages/ComicText',
          params: { requestId: requestId } });
      } catch (_) {
        ComicTextRequests.take(requestId);
        HdsFeedback.showToast(index === 4 ? '无法打开本页着色，请重试' : '无法打开文字识别，请重试');
      }
      return;
    }
    try {
      if (index === 0) {
        const saved = await ReaderComicImageExport.saveToAlbum(this.host.abilityContext(), source, snapshot);
        if (saved) HdsFeedback.showToast('已保存到相册');
      } else if (index === 1) {
        await ReaderComicImageExport.share(this.host.abilityContext(), source, snapshot);
      }
    } catch (error) {
      console.warn('漫画图片保存/分享失败:', error);
      HdsFeedback.showToast(index === 0 ? '保存失败，图片可能还没加载成功' : '分享失败，图片可能还没加载成功');
    }
  }

  onImageDenied(chapterIndex: number): void {
    if (this.host.isLocalBook() || this.refreshedChapters.has(chapterIndex)) return;
    if (chapterIndex !== this.host.currentChapter() || this.host.busy()) {
      this.deniedChapters.add(chapterIndex);
      return;
    }
    this.deniedChapters.delete(chapterIndex);
    this.refreshedChapters.add(chapterIndex);
    HdsFeedback.showToast('图片地址已过期，正在重新获取本话');
    this.host.refreshCurrentChapter();
  }

  /** 这一章刚成为当前章：它在相邻位置时被拒的图片现在处理。 */
  onChapterBecameCurrent(chapterIndex: number): void {
    if (this.deniedChapters.has(chapterIndex)) this.onImageDenied(chapterIndex);
  }
}
