import systemDateTime from '@ohos.systemDateTime';
import { AccountSessionStore } from './AccountSessionStore';

/** AI 限时体验活动只影响这三项端侧能力，不授予会员身份。 */
export class AiAccessPolicy {
  static readonly ENDS_AT: number = Date.parse('2026-11-11T00:00:00+08:00');
  static readonly TRIAL_LABEL: string = '限时免费 · 至 11 月 10 日（北京时间）';
  private static readonly ENDED_KEY: string = 'aiLaunchTrial20261111Ended';
  private static initialized: boolean = false;
  private static running: boolean = false;
  private static timer: number = -1;
  private static sampleKey: string = '';
  private static anchorTime: number = 0;
  private static anchorUptime: number = 0;
  private static calibrated: boolean = false;

  static initialize(): void {
    if (AiAccessPolicy.initialized) return;
    AiAccessPolicy.initialized = true;
    PersistentStorage.persistProp(AiAccessPolicy.ENDED_KEY, false);
    AppStorage.setOrCreate('aiTrialOpen', false);
  }

  /** 复用账号快照的服务端时间；同一进程用包含休眠时间的单调时钟推进。 */
  private static now(): number {
    const localNow = Date.now();
    let uptime = localNow;
    try { uptime = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false); } catch (_) {}
    const account = AccountSessionStore.account();
    const serverNow = account.membership?.serverNow || 0;
    const verifiedAt = account.memberVerifiedAt;
    const key = `${account.userId}:${serverNow}:${verifiedAt}`;
    if (serverNow > 0 && verifiedAt > 0 && key !== AiAccessPolicy.sampleKey) {
      AiAccessPolicy.sampleKey = key;
      AiAccessPolicy.anchorTime = serverNow + Math.max(0, localNow - verifiedAt);
      AiAccessPolicy.anchorUptime = uptime;
      AiAccessPolicy.calibrated = true;
    } else if (AiAccessPolicy.anchorTime === 0) {
      AiAccessPolicy.anchorTime = localNow;
      AiAccessPolicy.anchorUptime = uptime;
    }
    const estimated = AiAccessPolicy.anchorTime + Math.max(0, uptime - AiAccessPolicy.anchorUptime);
    return AiAccessPolicy.calibrated ? estimated : Math.max(localNow, estimated);
  }

  static trialOpen(): boolean {
    return !AppStorage.get<boolean>(AiAccessPolicy.ENDED_KEY) && AiAccessPolicy.now() < AiAccessPolicy.ENDS_AT;
  }

  static isAllowed(feature: string): boolean {
    if (feature !== 'super-resolution' && feature !== 'colorization' && feature !== 'translation') return false;
    if (AccountSessionStore.activeMembershipSku() !== '') return true;
    return AccountSessionStore.isLoggedIn() && AiAccessPolicy.trialOpen();
  }

  static actionText(): string {
    return AiAccessPolicy.trialOpen() && !AccountSessionStore.isLoggedIn() ? '登录后免费试用' : '开通会员';
  }

  static blockedMessage(): string {
    return AiAccessPolicy.trialOpen() ? '登录后免费试用，至 11 月 10 日（北京时间）' :
      '免费试用已结束，开通会员继续使用';
  }

  static start(): void {
    AiAccessPolicy.running = true;
    AiAccessPolicy.refresh();
  }

  static stop(): void {
    AiAccessPolicy.running = false;
    if (AiAccessPolicy.timer >= 0) clearTimeout(AiAccessPolicy.timer);
    AiAccessPolicy.timer = -1;
  }

  /** 由前台生命周期、账号变更及截止定时器触发，保持页面和推理权限一致。 */
  static refresh(): void {
    AiAccessPolicy.initialize();
    const now = AiAccessPolicy.now();
    if (now >= AiAccessPolicy.ENDS_AT) AppStorage.setOrCreate(AiAccessPolicy.ENDED_KEY, true);
    const open = !AppStorage.get<boolean>(AiAccessPolicy.ENDED_KEY) && now < AiAccessPolicy.ENDS_AT;
    if (AppStorage.get<boolean>('aiTrialOpen') !== open) AppStorage.setOrCreate('aiTrialOpen', open);
    if (AiAccessPolicy.timer >= 0) clearTimeout(AiAccessPolicy.timer);
    AiAccessPolicy.timer = -1;
    if (AiAccessPolicy.running && open) {
      AiAccessPolicy.timer = setTimeout((): void => AiAccessPolicy.refresh(),
        Math.max(1, Math.min(60000, AiAccessPolicy.ENDS_AT - now)));
    }
  }
}
