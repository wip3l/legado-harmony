import { AccountSessionStore } from './AccountSessionStore';

/** 自定义主题数量权益。额度只限制新增，不裁剪降级前保存的方案。 */
export class CustomThemeQuota {
  static forSku(sku: string): number {
    if (sku === 'MONTHLY') return 10;
    if (sku === 'ANNUAL') return 20;
    if (sku === 'LIFETIME') return 50;
    if (sku === 'SUPER_LIFETIME') return 100;
    return 5;
  }

  /** 显示新增方案所需的最低档位；免费额度内不显示会员标识。 */
  static minimumForCount(count: number): string {
    if (count <= CustomThemeQuota.forSku('')) return '';
    if (count <= CustomThemeQuota.forSku('MONTHLY')) return 'MONTHLY';
    if (count <= CustomThemeQuota.forSku('ANNUAL')) return 'ANNUAL';
    if (count <= CustomThemeQuota.forSku('LIFETIME')) return 'LIFETIME';
    return 'SUPER_LIFETIME';
  }

  static current(): number {
    return CustomThemeQuota.forSku(AccountSessionStore.activeMembershipSku());
  }
}
