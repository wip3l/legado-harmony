import { MembershipIcons } from './MembershipIcons';
import { CloudRemoteFont } from './CloudAutoSync';

/** 原生 Select 的云端字体标签；菜单布局、交互和选中态由系统绘制。 */
export class CloudFontMenu {
  static option(font: CloudRemoteFont): SelectOption {
    return { value: CloudFontMenu.label(font), icon: MembershipIcons.forSku('SUPER_LIFETIME') };
  }

  static label(font: CloudRemoteFont): string {
    const name = (font.name || '云端字体').replace(/\.(ttf|otf|ttc)$/i, '');
    return `${name}（未下载）`;
  }
}
