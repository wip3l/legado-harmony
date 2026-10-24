import { MembershipIcons } from '../../account/MembershipIcons';

/** 显示功能所需最低档位；关闭外显后，仅在当前会员等级不足时显示。 */
@Component
export struct MembershipBadge {
  @Prop sku: string = '';
  @StorageProp('accountMembershipSku') membershipSku: string = '';
  @StorageProp('memberSettingsVisible') settingsVisible: boolean = true;

  private shouldShow(): boolean {
    const required = MembershipIcons.SKUS.indexOf(this.sku);
    return required >= 0 && (this.settingsVisible || MembershipIcons.SKUS.indexOf(this.membershipSku) < required);
  }

  build() {
    if (this.shouldShow()) {
      Image(MembershipIcons.forSku(this.sku))
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)
        .flexShrink(0)
        .accessibilityText(`${MembershipIcons.label(this.sku)}起可用`)
    }
  }
}
