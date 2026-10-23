import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import image from '@ohos.multimedia.image';

/** 网络下载被拒绝时的兜底：截取阅读页里已经显示出来的这张图。 */
export type ReaderComicSnapshotProvider = () => Promise<image.PixelMap>;

/** 漫画图片导出：保存到相册（系统确认弹窗，无需相册权限）与系统分享。 */
export class ReaderComicImageExport {
  private static readonly MAX_BYTES: number = 30 * 1024 * 1024;

  /** 保存到相册；用户在系统弹窗里取消时返回 false。 */
  static async saveToAlbum(context: common.Context, source: string,
    snapshot: ReaderComicSnapshotProvider | null = null): Promise<boolean> {
    const path = await ReaderComicImageExport.materialize(context, source, snapshot);
    const extension = ReaderComicImageExport.sniffExtension(path);
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const targets = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(path)], [{
      title: `legado_${Date.now()}`,
      fileNameExtension: extension,
      photoType: photoAccessHelper.PhotoType.IMAGE
    }]);
    if (!targets || targets.length === 0 || !targets[0]) return false;
    const target = fs.openSync(targets[0], fs.OpenMode.WRITE_ONLY);
    try {
      fs.copyFileSync(path, target.fd);
    } finally {
      fs.closeSync(target);
    }
    return true;
  }

  static async share(context: common.UIAbilityContext, source: string,
    snapshot: ReaderComicSnapshotProvider | null = null): Promise<void> {
    const path = await ReaderComicImageExport.materialize(context, source, snapshot);
    const extension = ReaderComicImageExport.sniffExtension(path);
    const type = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(`.${extension}`,
      uniformTypeDescriptor.UniformDataType.IMAGE);
    const data = new systemShare.SharedData({ utd: type, uri: fileUri.getUriFromPath(path) });
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DETAIL,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  /**
   * 得到图片的本地文件路径：本地图直接用，网络图与 data: 落到缓存目录。
   * 网络图下载失败（防盗链、签名过期等）时退回截取已显示的图片，清晰度为屏幕显示尺寸。
   */
  private static async materialize(context: common.Context, source: string,
    snapshot: ReaderComicSnapshotProvider | null): Promise<string> {
    const value = (source || '').trim();
    if (!value) throw new Error('图片地址为空');
    if (/^file:/i.test(value)) return new fileUri.FileUri(value).path;
    if (!/^(?:https?:|data:)/i.test(value)) return value;
    let bytes: Uint8Array;
    try {
      bytes = /^data:/i.test(value) ? ReaderComicImageExport.decodeDataUri(value) :
        await ReaderComicImageExport.downloadImage(value);
    } catch (error) {
      if (!snapshot) throw error as Error;
      console.warn(`[ReaderComicExport] 下载原图失败，改用屏幕截取: ${(error as Error)?.message || error}`);
      bytes = await ReaderComicImageExport.encodeSnapshot(snapshot);
    }
    if (bytes.length === 0) throw new Error('图片内容为空');
    const dir = `${context.cacheDir}/comic_export`;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    ReaderComicImageExport.pruneOldFiles(dir);
    const path = `${dir}/${Date.now()}.${ReaderComicImageExport.extensionOfBytes(bytes)}`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes.buffer);
    } finally {
      fs.closeSync(file);
    }
    return path;
  }

  private static async encodeSnapshot(snapshot: ReaderComicSnapshotProvider): Promise<Uint8Array> {
    const pixelMap = await snapshot();
    const packer = image.createImagePacker();
    try {
      const data = await packer.packToData(pixelMap, { format: 'image/jpeg', quality: 95 });
      return new Uint8Array(data);
    } finally {
      await packer.release();
      await pixelMap.release();
    }
  }

  /** 带浏览器标识下载网络图片；超分也用它取原图。 */
  static async downloadImage(url: string): Promise<Uint8Array> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        // 不少图床拒绝没有浏览器标识的请求。
        header: {
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) ' +
            'Chrome/120.0.0.0 Mobile Safari/537.36'
        },
        connectTimeout: 15000,
        readTimeout: 30000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`图片下载失败（${response.responseCode}）`);
      }
      const buffer = response.result as ArrayBuffer;
      if (!buffer || buffer.byteLength > ReaderComicImageExport.MAX_BYTES) throw new Error('图片过大或为空');
      return new Uint8Array(buffer);
    } finally {
      request.destroy();
    }
  }

  private static decodeDataUri(value: string): Uint8Array {
    const comma = value.indexOf(',');
    if (comma < 0 || !/;base64$/i.test(value.substring(0, comma))) throw new Error('不支持的图片数据');
    return new util.Base64Helper().decodeSync(value.substring(comma + 1));
  }

  private static extensionOfBytes(bytes: Uint8Array): string {
    if (bytes.length >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) return 'jpg';
    if (bytes.length >= 4 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      return 'png';
    }
    if (bytes.length >= 4 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) return 'gif';
    if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return 'webp';
    }
    if (bytes.length >= 2 && bytes[0] === 0x42 && bytes[1] === 0x4D) return 'bmp';
    return 'jpg';
  }

  /** 按文件头判断格式；相册按扩展名校验图片类型，扩展名不符会拒绝写入。 */
  private static sniffExtension(path: string): string {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(12);
      const read = fs.readSync(file.fd, buffer);
      return ReaderComicImageExport.extensionOfBytes(new Uint8Array(buffer, 0, read));
    } finally {
      fs.closeSync(file);
    }
  }

  /** 导出缓存只为一次保存/分享服务，保留最近 20 个。 */
  private static pruneOldFiles(dir: string): void {
    try {
      const names = fs.listFileSync(dir).sort();
      for (let i = 0; i < names.length - 20; i++) fs.unlinkSync(`${dir}/${names[i]}`);
    } catch (_) {
    }
  }
}
