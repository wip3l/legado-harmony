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

  static current(): number {
    return CustomThemeQuota.forSku(AccountSessionStore.activeMembershipSku());
  }
}
