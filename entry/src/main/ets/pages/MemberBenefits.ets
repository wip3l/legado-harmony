import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountApiError } from '../account/AccountCommerceModels';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { MembershipIcons } from '../account/MembershipIcons';
import { MembershipCommerceService } from '../account/MembershipCommerceService';
import { MembershipGiftRules } from '../account/MembershipGiftRules';
import { MembershipSnapshot } from '../account/MembershipModels';
import { CloudFileClient } from '../account/CloudFileClient';
import { CloudFileSummary } from '../account/CloudFileModels';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeIds } from '../theme/ThemeModels';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';

/** 我的权益：每月礼包、专属主题等要手动领取的权益和其余权益状态集中在这页，入口在会员卡上。 */
@Entry
@Component
struct MemberBenefitsPage {
  @StorageLink('accountMembershipSku') membershipSku: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('accountEntitlementsRevision') entitlementsRevision: number = 0;
  @State membership: MembershipSnapshot = new MembershipSnapshot();
  @State memberBusy: boolean = false;
  @State cloudSummary: CloudFileSummary | null = null;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.membership = AccountSessionStore.account().membership || new MembershipSnapshot();
    this.syncBars();
    this.loadUsage();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Column() {
      PageScaffold({ title: '我的权益', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.LG }) {
      this.summaryCard()
      if (this.membershipSku) {
        if (MembershipGiftRules.included(this.membership, this.membershipSku) || this.membership.claim) {
          this.giftCard()
        } else {
          this.giftUpsell()
        }
        if (this.isSuperMember()) {
          this.exclusiveThemeCard()
        }
        this.benefitList()
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 14 })
  }

  loadUsage(): void {
    if (!AccountSessionStore.isLoggedIn()) return;
    if (this.isSuperMember()) {
      CloudFileClient.summary().then((summary: CloudFileSummary) => {
        this.cloudSummary = summary;
      }).catch(() => undefined);
    }
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  errorMessage(error: Object, fallback: string): string {
    const apiError = error as AccountApiError;
    return apiError?.message ? apiError.message : fallback;
  }

  isSuperMember(): boolean {
    return this.membershipSku === 'SUPER_LIFETIME';
  }

  formatDate(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
  }

  formatBytes(bytes: number): string {
    if (bytes >= 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
    if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
    return `${Math.max(0, Math.round(bytes / 1024))} KB`;
  }

  /** 还没领取的权益条数：本期礼包、专属主题。 */
  pendingCount(): number {
    const revision = this.entitlementsRevision;
    let count = MembershipGiftRules.pending(this.membership, this.membershipSku) ? 1 : 0;
    if (revision >= 0 && this.isSuperMember() && !AccountSessionStore.hasOwnedEntitlement(ThemeIds.OBSIDIAN_ARCHIVE)) {
      count++;
    }
    return count;
  }

  @Builder
  summaryCard() {
    Row({ space: AppSpacing.LG }) {
      if (this.membershipSku) {
        Image(MembershipIcons.forSku(this.membershipSku))
          .width(44)
          .height(44)
          .objectFit(ImageFit.Contain)
      }
      Column({ space: AppSpacing.XXS }) {
        Text(this.membershipSku ? MembershipIcons.label(this.membershipSku) : '暂无有效会员')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
        Text(!this.membershipSku ? '开通或恢复会员后，可在这里领取每月礼包与专属主题' :
          (this.pendingCount() > 0 ? `${this.pendingCount()} 项权益待领取` : '本期权益都已领取'))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(MembershipIcons.cardSubTextColor(this.appDarkMode))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .linearGradient({ angle: 135, colors: MembershipIcons.cardGradient(this.membershipSku, this.appDarkMode) })
  }

  // ---- 每月朗读礼包 ----

  giftChars(tier: string): number {
    if (this.membership.claim?.tier === tier) return this.membership.claim.chars;
    return this.ruleGiftChars(tier);
  }

  /** 当前档位按现行规则每月可领的字数，不看本期已领记录。 */
  ruleGiftChars(tier: string): number {
    const benefits = this.membership.benefits;
    if (this.membership.active && benefits) {
      return tier === 'STANDARD' ? benefits.standardGiftChars : benefits.premiumGiftChars;
    }
    if (this.membershipSku === 'MONTHLY' || !this.membershipSku) return 0;
    if (this.isSuperMember()) return tier === 'STANDARD' ? 12000 : 6000;
    if (this.membershipSku === 'LIFETIME') return tier === 'STANDARD' ? 8000 : 4000;
    return tier === 'STANDARD' ? 5000 : 2500;
  }

  giftPeriodText(): string {
    const cycle = this.membership.giftCycle;
    if (!cycle) return '标准或精品二选一';
    // Gift windows use Beijing time regardless of the device timezone; endsAt is exclusive.
    const first = new Date(cycle.startsAt + 8 * 60 * 60 * 1000);
    const last = new Date(cycle.endsAt - 1 + 8 * 60 * 60 * 1000);
    return `${first.getUTCFullYear()}年${first.getUTCMonth() + 1}月1日—${last.getUTCDate()}日（北京时间） · 二选一`;
  }

  /**
   * 本期领取记录按领取时的规则发放（旧规则或同月升级前的档位），字数与现行规则不同；
   * 已领卡片仍显示实际到账字数，这里补一句说明，免得和另一档的现行字数对比时看起来颠倒。
   */
  giftLegacyClaimText(): string {
    const claim = this.membership.claim;
    if (!claim || !this.membership.active) return '';
    const standard = this.ruleGiftChars('STANDARD');
    const premium = this.ruleGiftChars('PREMIUM');
    const current = claim.tier === 'STANDARD' ? standard : premium;
    if (current <= 0 || claim.chars === current) return '';
    return `本期 ${claim.chars} 字按领取时的规则发放，下月起每月可领标准 ${standard} 字或精品 ${premium} 字`;
  }

  async confirmClaim(tier: string, title: string): Promise<void> {
    const decision = await promptAction.showDialog({
      title: '领取本期礼包',
      message: `领取${title} ${this.giftChars(tier)} 字？每个自然月只能二选一，领取后不能更换；已领字数可累计使用。`,
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '领取', color: this.accentColor() }]
    });
    if (decision.index === 1) await this.claimGift(tier);
  }

  async claimGift(tier: string): Promise<void> {
    if (this.memberBusy || this.membership.claim) return;
    this.memberBusy = true;
    try {
      const result = await AccountCommerceApi.claimMembershipGift(tier, AccountSessionStore.token());
      this.membership = result.membership;
      // 写回账号快照，返回会员页时入口提示随之更新。
      const account = AccountSessionStore.account();
      account.membership = result.membership;
      account.memberVerifiedAt = Date.now();
      await AccountSessionStore.updateSnapshot(this.context, account);
      HdsFeedback.showToast('朗读额度已到账');
    } catch (e) {
      HdsFeedback.showToast(this.errorMessage(e, '领取失败，请刷新后重试'));
    } finally {
      this.memberBusy = false;
    }
  }

  @Builder
  giftUpsell() {
    Row({ space: AppSpacing.LG }) {
      SymbolGlyph($r('sys.symbol.book_pages'))
        .fontSize(20)
        .fontColor([MembershipIcons.nameColor('ANNUAL', this.appDarkMode)])
      Column({ space: AppSpacing.XXS }) {
        Text('月度会员不含每月朗读礼包')
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
        Text('年度会员起每月可领标准 5000 字或精品 2500 字')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('去升级')
        .fontSize(AppFontSize.BODY)
        .fontColor(MembershipIcons.nameColor('ANNUAL', this.appDarkMode))
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .onClick(() => {
      router.back();
    })
  }

  @Builder
  giftCard() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Column({ space: AppSpacing.XXS }) {
          Text('本期朗读礼包')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(this.giftPeriodText())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.membership.claim) {
          Text('已领取')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.successColor(this.appDarkMode))
        }
      }
      .width('100%')
      Row({ space: AppSpacing.MD }) {
        this.giftTile('STANDARD', '标准音色')
        this.giftTile('PREMIUM', '精品音色')
      }
      .width('100%')
      if (this.giftLegacyClaimText()) {
        Text(this.giftLegacyClaimText())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.primaryTextColor())
      }
      Text('已领字数在连续会员期内有效，终身会员可累计使用')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  giftTile(tier: string, title: string) {
    Column({ space: AppSpacing.XXS }) {
      Row({ space: AppSpacing.XS }) {
        Text(`${this.giftChars(tier)}`)
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.membership.claim && this.membership.claim.tier !== tier ? this.subTextColor() :
            this.primaryTextColor())
        Text('字')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .alignItems(VerticalAlign.Bottom)
      Text(this.membership.claim?.tier === tier ? `${title} · 已领取` : title)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.membership.claim?.tier === tier ? ThemeRuntime.successColor(this.appDarkMode) :
          this.subTextColor())
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(this.inputColor())
    .border({ width: this.membership.claim?.tier === tier ? 1.5 : 0,
      color: ThemeRuntime.successColor(this.appDarkMode) })
    .opacity(this.membership.claim && this.membership.claim.tier !== tier ? 0.55 : 1)
    .onClick(() => {
      if (!this.membership.claim) this.confirmClaim(tier, title);
    })
  }

  // ---- 专属主题 ----

  exclusiveThemeHint(): string {
    const revision = this.entitlementsRevision;
    const owned = AccountSessionStore.entitlement(ThemeIds.OBSIDIAN_ARCHIVE);
    return revision >= 0 && owned && AccountSessionStore.hasOwnedEntitlement(ThemeIds.OBSIDIAN_ARCHIVE) ?
      `已领取 · 有效至 ${this.formatDate(owned.expiresAt)}` : '每次领取一年，到期后可再次领取 · 不支持点数购买';
  }

  async claimExclusiveTheme(): Promise<void> {
    if (this.memberBusy) return;
    if (AccountSessionStore.hasOwnedEntitlement(ThemeIds.OBSIDIAN_ARCHIVE)) {
      router.pushUrl({ url: 'pages/ThemeSettings', params: { themeId: ThemeIds.OBSIDIAN_ARCHIVE } });
      return;
    }
    const choice = await promptAction.showDialog({ title: '领取「曜金藏书」',
      message: '终身超级会员专属，不扣除点数。领取后有效一年，到期后可再次手动领取。',
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '领取一年', color: this.accentColor() }] });
    if (choice.index !== 1) return;
    this.memberBusy = true;
    try {
      await MembershipCommerceService.claimSuperTheme(getContext(this), ThemeIds.OBSIDIAN_ARCHIVE);
      HdsFeedback.showToast('已领取「曜金藏书」，可在主题设置中应用');
    } catch (e) {
      HdsFeedback.showToast((e as Error).message || '领取失败，请稍后重试');
    } finally { this.memberBusy = false; }
  }

  @Builder
  exclusiveThemeCard() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        Image($r('app.media.theme_cover_obsidian_archive_01'))
          .width(62).height(86).objectFit(ImageFit.Cover).borderRadius(7)
        Column({ space: AppSpacing.XS }) {
          Text('专属主题 · 曜金藏书').fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
          Text('曜黑藏书，香槟描金').fontSize(AppFontSize.BODY).fontColor(this.accentColor())
          Text(this.exclusiveThemeHint()).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      Button(AccountSessionStore.hasOwnedEntitlement(ThemeIds.OBSIDIAN_ARCHIVE) ? '已领取 · 查看主题' : '领取一年')
        .width('100%').height(42).fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.onAccentColor(this.accentColor())).backgroundColor(this.accentColor())
        .enabled(!this.memberBusy).onClick(() => this.claimExclusiveTheme())
    }.width('100%').padding(AppSpacing.LG).borderRadius(ThemeRuntime.cardRadius())
      .backgroundColor(this.cardColor())
  }

  // ---- 其余权益 ----

  largeSourceSyncText(): string {
    return this.isSuperMember() ? '单个书源最大 960KB · 已生效' : '终身超级会员专享 · 单个书源最大 960KB';
  }

  cloudSpaceText(): string {
    if (!this.isSuperMember()) return '终身超级会员专享';
    if (!this.cloudSummary) return '书籍、字体与书源共用 1GB';
    if (!this.cloudSummary.configured) return '云空间服务尚未启用';
    return `已用 ${this.formatBytes(this.cloudSummary.usedBytes)} / 1GB · 本月下载 ` +
      `${this.formatBytes(this.cloudSummary.downloadBytes)}`;
  }

  @Builder
  benefitList() {
    Column() {
      this.benefitRow($r('sys.symbol.speaker_wave_2'), '在线朗读优先排队', '高峰期优先 · 已生效', true, undefined)
      this.benefitRow($r('sys.symbol.picture'), '漫画超分', '漫画阅读 → 画面设置中开启', true, undefined)
      this.benefitRow($r('sys.symbol.arrow_2_circlepath'), '超大书源同步', this.largeSourceSyncText(), true, undefined)
      this.benefitRow($r('sys.symbol.star'), '功能尝鲜', '新功能优先试用', true, undefined)
      this.benefitRow($r('sys.symbol.paintpalette'), '高级主题自定义', '即将推出', true, undefined)
      if (this.membershipSku === 'LIFETIME' || this.isSuperMember()) {
        this.benefitRow($r('sys.symbol.person'), '动态头像', '支持 GIF / WebP 动图，可在会员与账号页编辑头像', true, undefined)
      }
      if (this.isSuperMember()) {
        this.benefitRow($r('sys.symbol.textformat'), '上传字体云端同步', '导入即上传，换机可选', true, undefined)
        this.benefitRow($r('sys.symbol.book_pages'), '本地书籍云端同步', '加入书架即上传', true, undefined)
        this.benefitRow($r('sys.symbol.arrow_down'), '每月下载额度', '每月 1GB · 云空间下载', true, undefined)
      }
      this.benefitRow($r('sys.symbol.paintpalette'), '会员主题库', '现有及新增会员主题，可直接应用', true, () => {
        router.pushUrl({ url: 'pages/ThemeSettings' });
      })
      if (this.isSuperMember()) {
        this.benefitRow($r('sys.symbol.folder'), '我的云空间', this.cloudSpaceText(), false, () => {
          router.pushUrl({ url: 'pages/CloudFiles' });
        })
      } else {
        this.benefitRow($r('sys.symbol.folder'), '我的云空间', this.cloudSpaceText(), false, undefined)
      }
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  @Builder
  benefitRow(icon: Resource, title: string, detail: string, showDivider: boolean, onClick?: () => void) {
    Column() {
      Row({ space: AppSpacing.LG }) {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([this.accentColor()])
          .width(28)
        Column({ space: AppSpacing.XXS }) {
          Text(title)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
          Text(detail)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (onClick) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([this.subTextColor()])
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 60 })
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
      .alignItems(VerticalAlign.Center)
      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(this.dividerColor())
          .margin({ left: 56, right: AppSpacing.XL })
      }
    }
    .width('100%')
    .onClick(() => {
      if (onClick) onClick();
    })
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  dividerColor(): string {
    return ThemeRuntime.hairlineColor(this.appDarkMode);
  }
}
