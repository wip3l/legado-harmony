import image from '@ohos.multimedia.image';
import { ComicColorSize } from './ComicColorPixels';

/** The buffer is RGBA. The platform defaults the SOURCE buffer to BGRA unless specified. */
export class ComicColorCodec {
  static async jpeg(rgba: Uint8Array, size: ComicColorSize): Promise<ArrayBuffer> {
    const map = await image.createPixelMap(rgba.buffer, { size: size,
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888, editable: false });
    const packer = image.createImagePacker();
    try {
      return await packer.packToData(map, { format: 'image/jpeg', quality: 95 });
    } finally {
      await packer.release();
      await map.release();
    }
  }
}
