import { MembershipBadge } from './MembershipBadge';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { AppFontSize } from '../../theme/AppFontSize';

/**
 * 操作菜单（长按菜单、“更多”菜单）的一行。外层是系统弹出层（bindPopup + ImmersiveMaterialRuntime.popupMenuOptions），
 * API 26+ 由系统画沉浸光感材质；这里只画图标、文字和按压反馈，圆角与弹出层同心。
 */
@Builder
export function PopupMenuAction(icon: Resource | undefined, label: string, color: string, action: () => void,
  enabled: boolean = true, badge: string = '', badgeColor: string = '', minimumMembership: string = '') {
  Row({ space: 10 }) {
    if (icon !== undefined) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([color])
        .width(22)
    }
    Row({ space: 4 }) {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
      if (minimumMembership) {
        MembershipBadge({ sku: minimumMembership })
      }
    }
    .layoutWeight(1)
    if (badge) {
      Text(badge)
        .fontSize(AppFontSize.MICRO)
        .fontColor(badgeColor || color)
    }
  }
  .width('100%')
  .height(44)
  .padding({ left: 12, right: 12 })
  .borderRadius(ImmersiveMaterialRuntime.POPUP_MENU_RADIUS - ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  .stateStyles({
    normal: {
      .backgroundColor(Color.Transparent)
    },
    pressed: {
      .backgroundColor('#1A808080')
    }
  })
  .opacity(enabled ? 1 : 0.38)
  .enabled(enabled)
  .onClick(action)
}

/** 操作菜单顶部的小标题，如“已选择 3 个书源”。 */
@Builder
export function PopupMenuHeader(title: string, color: string) {
  Text(title)
    .fontSize(AppFontSize.CAPTION)
    .fontColor(color)
    .width('100%')
    .height(34)
    .padding({ left: 12, right: 12 })
}
