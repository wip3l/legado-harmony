import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { iap } from '@kit.IAPKit';
import { util } from '@kit.ArkTS';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { AccountCommerceConfig } from '../account/AccountCommerceConfig';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import {
  AccountApiError,
  AvatarCrop,
  IapCreditResponse,
  RechargeProduct
} from '../account/AccountCommerceModels';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { MembershipIcons } from '../account/MembershipIcons';
import { MembershipCommerceService } from '../account/MembershipCommerceService';
import { MembershipGiftRules } from '../account/MembershipGiftRules';
import { MembershipOrder, MembershipProduct, MembershipPromotion, MembershipSnapshot } from '../account/MembershipModels';
import { CloudSyncSummary } from '../account/CloudSyncModels';
import { HuaweiAccountService } from '../account/HuaweiAccountService';
import { CloudAutoSync } from '../account/CloudAutoSync';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeIds } from '../theme/ThemeModels';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';

class BenefitCompareRow {
  title: string;
  note: string;
  values: string[];

  constructor(title: string, note: string, values: string[]) {
    this.title = title;
    this.note = note;
    this.values = values;
  }
}

/** 会员与账号：身份、点数、会员开通/续费/升级、礼包、云空间和充值合在一页。 */
@Entry
@Component
struct AccountCenterPage {
  @StorageLink('accountMembershipSku') membershipSku: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('accountLoggedIn') accountLoggedIn: boolean = false;
  @StorageLink('accountDisplayName') displayName: string = '';
  @StorageLink('accountAvatarUrl') avatarUrl: string = '';
  @StorageLink('accountPoints') points: number = 0;
  @StorageLink('accountPaidPoints') paidPoints: number = 0;
  @StorageLink('accountPromoPoints') promoPoints: number = 0;
  @StorageLink('accountEntitlementsRevision') entitlementsRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State loading: boolean = false;
  @State purchasingProductId: string = '';
  @State products: RechargeProduct[] = AccountCommerceConfig.rechargeProducts();
  @State memberProducts: MembershipProduct[] = [];
  @State membership: MembershipSnapshot = new MembershipSnapshot();
  @State @Watch('revealSelectedCompareColumn') selectedSku: string = 'ANNUAL';
  @State memberBusy: boolean = false;
  @State agreed: boolean = false;
  @State memberError: string = '';
  @State orders: MembershipOrder[] = [];
  @State ordersExpanded: boolean = false;
  @State sourceUsage: CloudSyncSummary = new CloudSyncSummary();
  @State showRechargeSheet: boolean = false;
  @State compareExpanded: boolean = false;
  @State editingProfile: boolean = false;
  @State profileNameInput: string = '';
  @State profileAvatarPreview: string = '';
  @State profileAvatarPixelMap: image.PixelMap | null = null;
  @State profileAvatarBase64: string = '';
  @State profileAvatarCrop: AvatarCrop | null = null;
  @State profileAvatarSourceWidth: number = 0;
  @State profileAvatarSourceHeight: number = 0;
  @State cropAnimated: boolean = false;
  @State removeProfileAvatar: boolean = false;
  @State savingProfile: boolean = false;
  @State croppingAvatar: boolean = false;
  @State cropSourceUri: string = '';
  @State cropSourceWidth: number = 0;
  @State cropSourceHeight: number = 0;
  @State cropZoom: number = 1;
  @State cropOffsetX: number = 0;
  @State cropOffsetY: number = 0;
  @State processingCrop: boolean = false;
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;
  private cropPanOriginX: number = 0;
  private cropPanOriginY: number = 0;
  private readonly cropBoxSize: number = 280;
  private readonly purchaseBarHeight: number = 116;
  // 权益对比表：左侧权益名固定，五个档位列横向滑动；行高固定，两边才能对齐。
  private readonly compareTitleWidth: number = 112;
  // 列宽按可视宽度决定一屏显示几列，见 Scroll 的 onAreaChange。
  @State compareColumnWidth: number = 88;
  private readonly compareHeaderHeight: number = 84;
  private readonly compareRowHeight: number = 54;
  private compareScroller: Scroller = new Scroller();
  private compareViewportWidth: number = 0;
  private pointsUsageDialogBuilder: CustomBuilder | undefined = undefined;
  private pointsUsageDialogId: number = -1;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.membership = AccountSessionStore.account().membership || new MembershipSnapshot();
    this.initialize();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
    // 从我的权益页领取礼包后返回，入口提示要跟着更新。
    if (this.accountLoggedIn) {
      this.membership = AccountSessionStore.account().membership || new MembershipSnapshot();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      PageScaffold({ title: '会员与账号', bottomInset: this.showPurchaseBar() ? 32 + this.purchaseBarHeight : 32,
        content: () => {
          this.pageContent()
        }, actions: () => {
          this.titleActions()
        } })
      if (this.showPurchaseBar()) {
        this.purchaseBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showRechargeSheet, this.rechargeSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: this.cardColor(),
      onDisappear: () => {
        this.showRechargeSheet = false;
      }
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = this.areaDimension(newValue.width);
      const height = this.areaDimension(newValue.height);
      if (width > 0 && Math.abs(width - this.viewportWidth) >= 1) {
        this.viewportWidth = width;
      }
      if (height > 0 && Math.abs(height - this.viewportHeight) >= 1) {
        this.viewportHeight = height;
      }
    })
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.LG }) {
      if (this.editingProfile && this.accountLoggedIn) {
        if (this.croppingAvatar) {
          this.avatarCropper()
        } else {
          this.profileEditor()
        }
      } else {
        this.memberCard()
        if (this.membership.restricted) {
          this.noticeBanner('账号存在退款欠款，会员权益已暂停。充值后会自动抵扣，补齐即恢复。')
        }
        if (this.memberError) {
          Text(this.memberError)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .width('100%')
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
        }
        if (this.purchasableProducts().length > 0) {
          this.planSection()
        }
        // 终身超级会员已是最高档，对比表收成一行，需要时再展开。
        if (this.isSuperMember() && !this.compareExpanded) {
          this.compareEntry()
        } else {
          this.benefitsCard()
        }
        if (this.accountLoggedIn) {
          this.serviceList()
          this.accountActions()
        } else {
          this.loginGuide()
        }
        this.serviceHint()
      }
    }
    .width('100%')
    .padding({
      left: AppSpacing.LG,
      right: AppSpacing.LG,
      top: 14
    })
  }

  @Builder
  titleActions() {
    if (this.accountLoggedIn) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(21)
        .fontColor([this.accentColor()])
        .width(48)
        .height(48)
        .onClick(() => {
          this.refreshAccount();
        })
    }
  }

  async initialize(): Promise<void> {
    try {
      await HuaweiAccountService.initialize(this.context);
      if (AccountSessionStore.isLoggedIn() && AccountCommerceConfig.isServerConfigured()) {
        await this.refreshMembership(true);
        await this.loadIapProducts();
        await this.recoverUnfinishedPurchases();
      } else if (AccountCommerceConfig.isServerConfigured()) {
        await this.refreshMembership(false);
      }
    } catch (e) {
      console.warn('初始化账号中心失败:', e);
    }
  }

  async login(): Promise<void> {
    if (this.loading) {
      return;
    }
    if (!AccountCommerceConfig.isServerConfigured()) {
      HdsFeedback.showToast('请先配置账号服务端地址');
      return;
    }
    this.loading = true;
    try {
      await HuaweiAccountService.login(this.context);
      // 换设备登录后立即拉取云空间的书籍与字体，不必等回到前台或打开云空间页。
      CloudAutoSync.schedule(this.context, 0);
      HdsFeedback.showToast('登录成功，点数、会员和主题权益已同步');
      await this.refreshMembership(false);
      await this.loadIapProducts();
      await this.recoverUnfinishedPurchases();
    } catch (e) {
      const error = e as BusinessError;
      // 1001502012: the user dismissed the authorization sheet.
      if (error.code !== 1001502005 && error.code !== 1001502012) {
        HdsFeedback.showToast(this.errorMessage(e, '华为账号登录失败'));
      }
    } finally {
      this.loading = false;
    }
  }

  async refreshAccount(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      await this.refreshMembership(true);
      CloudAutoSync.schedule(this.context, 0);
      if (!this.memberError) HdsFeedback.showToast('账号数据已同步');
    } finally {
      this.loading = false;
    }
  }

  /**
   * 读取会员目录与账号快照。fetchAccount 为 true 时重新拉取账号；登录流程刚拉取过时传 false。
   * 未完成的会员购买先按原请求标识重试，结果不确定时不影响账号刷新。
   */
  async refreshMembership(fetchAccount: boolean): Promise<void> {
    if (this.memberBusy) return;
    this.memberBusy = true;
    this.memberError = '';
    try {
      const token = AccountSessionStore.isLoggedIn() ? AccountSessionStore.token() : '';
      try {
        this.memberProducts = (await AccountCommerceApi.fetchMembershipCatalog(token)).products || [];
        this.ensureSelectableSku();
      } catch (e) {
        this.memberError = this.errorMessage(e, '会员方案暂时无法加载，请稍后刷新');
      }
      if (!AccountSessionStore.isLoggedIn()) return;
      try {
        await MembershipCommerceService.recover(this.context);
      } catch (e) {
        this.memberError = this.errorMessage(e, '上次会员购买仍在确认，请稍后刷新');
      }
      if (fetchAccount) {
        await HuaweiAccountService.refresh(this.context);
      }
      this.membership = AccountSessionStore.account().membership || new MembershipSnapshot();
      AccountCommerceApi.fetchSyncSummary(AccountSessionStore.token()).then((summary: CloudSyncSummary) => {
        this.sourceUsage = summary;
      }).catch(() => undefined);
    } catch (e) {
      this.memberError = this.errorMessage(e, '账号数据同步失败，请稍后刷新');
    } finally {
      this.memberBusy = false;
    }
  }

  ensureSelectableSku(): void {
    const selected = this.selectedProduct();
    if (selected && selected.salesEnabled && this.purchaseBlockReason(selected) === '') return;
    const available = this.memberProducts.find((item: MembershipProduct) =>
      item.salesEnabled && this.purchaseBlockReason(item) === '');
    if (available) {
      this.selectedSku = available.sku;
    } else if (this.membershipSku) {
      // 没有可买的档位（终身超级会员）时，对比表停在当前档位。
      this.selectedSku = this.membershipSku;
    }
  }

  async logout(): Promise<void> {
    const result = await promptAction.showDialog({
      title: '退出登录',
      message: '点数、会员和主题权益仍保存在云端，下次登录后会自动恢复。',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '退出', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    await HuaweiAccountService.logout(this.context);
    // 退出后字体下拉框不再显示云端未下载的字体。
    CloudAutoSync.schedule(this.context, 0);
    this.editingProfile = false;
    this.membership = new MembershipSnapshot();
    this.orders = [];
    this.ordersExpanded = false;
    HdsFeedback.showToast('已退出登录');
  }

  beginEditProfile(): void {
    this.releaseProfileAvatarPreview();
    this.profileNameInput = this.displayName || '华为用户';
    this.profileAvatarPreview = this.avatarUrl;
    this.profileAvatarBase64 = '';
    this.profileAvatarCrop = null;
    this.removeProfileAvatar = false;
    this.editingProfile = true;
  }

  cancelEditProfile(): void {
    if (this.savingProfile || this.processingCrop) {
      return;
    }
    this.editingProfile = false;
    this.croppingAvatar = false;
    this.profileAvatarBase64 = '';
    this.releaseProfileAvatarPreview();
  }

  async pickProfileAvatar(): Promise<void> {
    if (this.savingProfile) {
      return;
    }
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new picker.PhotoViewPicker(this.context).select(options);
      if (!result || result.photoUris.length === 0) {
        return;
      }
      const uri = result.photoUris[0];
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      if (!info.size.width || !info.size.height) {
        throw new Error('无法读取图片尺寸');
      }
      const frames = await source.getFrameCount();
      if (frames > 1) {
        if (!await this.ensureAnimatedAvatarAccess()) return;
        if (fs.statSync(file.fd).size > 2 * 1024 * 1024 || frames > 120 ||
          info.size.width > 1024 || info.size.height > 1024 ||
          info.size.width * info.size.height * frames > 32 * 1024 * 1024) {
          HdsFeedback.showToast('请选择 2MB 内、最多 120 帧、单帧不超过 1024×1024 的较小动图');
          return;
        }
      }
      this.cropAnimated = frames > 1;
      this.cropSourceUri = uri;
      this.cropSourceWidth = info.size.width;
      this.cropSourceHeight = info.size.height;
      this.cropZoom = 1;
      this.cropOffsetX = 0;
      this.cropOffsetY = 0;
      this.croppingAvatar = true;
    } catch (e) {
      console.error('选择账号头像失败:', e);
      HdsFeedback.showToast('头像读取失败，请换一张图片重试');
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (e) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (e) {
        }
      }
    }
  }

  cancelAvatarCrop(): void {
    if (this.processingCrop) {
      return;
    }
    this.croppingAvatar = false;
    this.cropSourceUri = '';
  }

  async confirmAvatarCrop(): Promise<void> {
    if (this.processingCrop || !this.cropSourceUri) {
      return;
    }
    this.processingCrop = true;
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      file = fs.openSync(this.cropSourceUri, fs.OpenMode.READ_ONLY);
      if (this.cropAnimated) {
        if (!this.canUseAnimatedAvatar()) {
          HdsFeedback.showToast('动态头像仅限有效的终身会员和终身超级会员使用');
          return;
        }
        const size = fs.statSync(file.fd).size;
        if (size <= 0 || size > 2 * 1024 * 1024) throw new Error('动态头像大小不能超过 2MB');
        const bytes = new Uint8Array(size);
        let read = 0;
        while (read < size) {
          const chunk = new ArrayBuffer(size - read);
          const count = await fs.read(file.fd, chunk, { offset: read, length: chunk.byteLength });
          if (count <= 0) throw new Error('动态头像读取不完整');
          bytes.set(new Uint8Array(chunk, 0, count), read);
          read += count;
        }
        const crop = new AvatarCrop();
        crop.size = Math.max(1, Math.round(Math.min(this.cropSourceWidth, this.cropSourceHeight) / this.cropZoom));
        crop.left = Math.round((this.cropSourceWidth - crop.size) * (this.cropOffsetX + 1) / 2);
        crop.top = Math.round((this.cropSourceHeight - crop.size) * (this.cropOffsetY + 1) / 2);
        this.profileAvatarBase64 = new util.Base64Helper().encodeToStringSync(bytes);
        this.releaseProfileAvatarPreview();
        this.profileAvatarCrop = crop;
        this.profileAvatarSourceWidth = this.cropSourceWidth;
        this.profileAvatarSourceHeight = this.cropSourceHeight;
        this.profileAvatarPreview = this.cropSourceUri;
        this.removeProfileAvatar = false;
        this.croppingAvatar = false;
        this.cropSourceUri = '';
        HdsFeedback.showToast('动态头像裁剪完成，保存后生效');
        return;
      }
      source = image.createImageSource(file.fd);
      // Decode to a bounded working image first. Supplying desiredRegion and
      // desiredSize together lets some decoders scale before cropping, which
      // makes a region calculated from the original image invalid.
      const maxSourceSize = Math.max(this.cropSourceWidth, this.cropSourceHeight);
      const decodeScale = Math.min(1, 2048 / Math.max(1, maxSourceSize));
      const decodeWidth = Math.max(1, Math.round(this.cropSourceWidth * decodeScale));
      const decodeHeight = Math.max(1, Math.round(this.cropSourceHeight * decodeScale));
      pixelMap = await source.createPixelMap({
        desiredSize: {
          width: decodeWidth,
          height: decodeHeight
        }
      });
      const decodedInfo = await pixelMap.getImageInfo();
      const workingWidth = decodedInfo.size.width;
      const workingHeight = decodedInfo.size.height;
      const workingMinSize = Math.min(workingWidth, workingHeight);
      const cropSize = Math.max(1, Math.min(workingMinSize, Math.round(workingMinSize / this.cropZoom)));
      const cropX = this.clamp(
        Math.round((workingWidth - cropSize) * (this.cropOffsetX + 1) / 2),
        0,
        Math.max(0, workingWidth - cropSize)
      );
      const cropY = this.clamp(
        Math.round((workingHeight - cropSize) * (this.cropOffsetY + 1) / 2),
        0,
        Math.max(0, workingHeight - cropSize)
      );
      await pixelMap.crop({
        x: cropX,
        y: cropY,
        size: {
          width: cropSize,
          height: cropSize
        }
      });
      const croppedInfo = await pixelMap.getImageInfo();
      await pixelMap.scale(
        256 / Math.max(1, croppedInfo.size.width),
        256 / Math.max(1, croppedInfo.size.height)
      );
      packer = image.createImagePacker();
      const packed = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 82,
        bufferSize: 512 * 1024
      });
      this.profileAvatarBase64 =
        new util.Base64Helper().encodeToStringSync(new Uint8Array(packed));
      this.releaseProfileAvatarPreview();
      this.profileAvatarPixelMap = pixelMap;
      this.profileAvatarCrop = null;
      pixelMap = null;
      this.profileAvatarPreview = '';
      this.removeProfileAvatar = false;
      this.croppingAvatar = false;
      this.cropSourceUri = '';
      HdsFeedback.showToast('头像裁剪完成');
    } catch (e) {
      console.error('裁剪账号头像失败:', e);
      HdsFeedback.showToast('头像裁剪失败，请换一张图片重试');
    } finally {
      if (pixelMap) {
        try {
          await pixelMap.release();
        } catch (e) {
        }
      }
      if (source) {
        try {
          await source.release();
        } catch (e) {
        }
      }
      if (packer) {
        try {
          await packer.release();
        } catch (e) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (e) {
        }
      }
      this.processingCrop = false;
    }
  }

  startCropPan(): void {
    this.cropPanOriginX = this.cropOffsetX;
    this.cropPanOriginY = this.cropOffsetY;
  }

  updateCropPan(event: GestureEvent): void {
    const maxX = this.cropMaxTranslateX();
    const maxY = this.cropMaxTranslateY();
    if (maxX > 0) {
      this.cropOffsetX = this.clamp(
        this.cropPanOriginX - event.offsetX / maxX, -1, 1);
    }
    if (maxY > 0) {
      this.cropOffsetY = this.clamp(
        this.cropPanOriginY - event.offsetY / maxY, -1, 1);
    }
  }

  cropPreviewWidth(): number {
    const minSize = Math.max(1, Math.min(this.cropSourceWidth, this.cropSourceHeight));
    return this.cropBoxSize * this.cropSourceWidth / minSize * this.cropZoom;
  }

  cropPreviewHeight(): number {
    const minSize = Math.max(1, Math.min(this.cropSourceWidth, this.cropSourceHeight));
    return this.cropBoxSize * this.cropSourceHeight / minSize * this.cropZoom;
  }

  cropMaxTranslateX(): number {
    return Math.max(0, (this.cropPreviewWidth() - this.cropBoxSize) / 2);
  }

  cropMaxTranslateY(): number {
    return Math.max(0, (this.cropPreviewHeight() - this.cropBoxSize) / 2);
  }

  clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  useDefaultAvatar(): void {
    this.releaseProfileAvatarPreview();
    this.profileAvatarPreview = '';
    this.profileAvatarBase64 = '';
    this.profileAvatarCrop = null;
    this.removeProfileAvatar = true;
  }

  async saveProfile(): Promise<void> {
    if (this.savingProfile) {
      return;
    }
    const displayName = this.profileNameInput.trim();
    if (!displayName || displayName.length > 30) {
      HdsFeedback.showToast('昵称应为 1 至 30 个字符');
      return;
    }
    this.savingProfile = true;
    try {
      if (this.profileAvatarCrop && !await this.ensureAnimatedAvatarAccess()) return;
      await HuaweiAccountService.updateProfile(
        this.context, displayName, this.profileAvatarBase64, this.removeProfileAvatar, this.profileAvatarCrop);
      this.editingProfile = false;
      this.profileAvatarBase64 = '';
      this.releaseProfileAvatarPreview();
      HdsFeedback.showToast('个人资料已保存，并会随账号跨设备同步');
    } catch (e) {
      HdsFeedback.showToast(this.errorMessage(e, '个人资料保存失败'));
    } finally {
      this.savingProfile = false;
    }
  }

  releaseProfileAvatarPreview(): void {
    const preview = this.profileAvatarPixelMap;
    this.profileAvatarPixelMap = null;
    if (preview) {
      preview.release().catch((e: Error) => {
        console.warn('释放头像裁剪预览失败:', e);
      });
    }
  }

  canUseAnimatedAvatar(): boolean {
    const account = AccountSessionStore.account();
    const member = account.membership;
    const state = member?.state;
    return this.accountLoggedIn && account.iapDebtPoints <= 0 && member !== null &&
      member.active && !member.restricted && state !== null && state !== undefined &&
      state.expiresAt === null && (state.sku === 'LIFETIME' || state.sku === 'SUPER_LIFETIME');
  }

  async ensureAnimatedAvatarAccess(): Promise<boolean> {
    try {
      // 旧缓存或旧服务端缺少新字段，并不代表用户没有终身会员身份。
      await HuaweiAccountService.refresh(this.context);
      this.membership = AccountSessionStore.account().membership || new MembershipSnapshot();
      if (!this.canUseAnimatedAvatar()) {
        HdsFeedback.showToast('动态头像仅限有效的终身会员和终身超级会员使用');
        return false;
      }
      if (this.membership.benefits?.animatedAvatar !== true) {
        HdsFeedback.showToast('动态头像服务暂未就绪，请稍后重试');
        return false;
      }
      return true;
    } catch (e) {
      HdsFeedback.showToast(this.errorMessage(e, '暂时无法核验动态头像权限，请稍后重试'));
      return false;
    }
  }

  async loadIapProducts(): Promise<void> {
    try {
      await iap.queryEnvironmentStatus(this.context);
      const productIds: string[] = [];
      for (const product of this.products) {
        productIds.push(product.productId);
      }
      const result = await iap.queryProducts(this.context, {
        productType: iap.ProductType.CONSUMABLE,
        productIds: productIds
      });
      const next = AccountCommerceConfig.rechargeProducts();
      for (const product of next) {
        for (const remote of result) {
          if (remote.id === product.productId) {
            product.localPrice = remote.localPrice || '';
            break;
          }
        }
      }
      this.products = next;
    } catch (e) {
      console.warn('加载IAP商品失败:', e);
    }
  }

  async buy(product: RechargeProduct): Promise<void> {
    if (this.purchasingProductId) {
      return;
    }
    if (!this.accountLoggedIn) {
      HdsFeedback.showToast('请先登录华为账号');
      return;
    }
    this.purchasingProductId = product.productId;
    try {
      const result = await iap.createPurchase(this.context, {
        productId: product.productId,
        productType: iap.ProductType.CONSUMABLE
      });
      await this.deliverAndFinish(result.purchaseData);
    } catch (e) {
      const error = e as BusinessError;
      if (error.code === iap.IAPErrorCode.PRODUCT_OWNED ||
        error.code === iap.IAPErrorCode.SYSTEM_ERROR) {
        await this.recoverUnfinishedPurchases();
      } else {
        HdsFeedback.showToast(this.errorMessage(e, '支付未完成'));
      }
    } finally {
      this.purchasingProductId = '';
    }
  }

  async recoverUnfinishedPurchases(): Promise<void> {
    if (!this.accountLoggedIn) {
      return;
    }
    try {
      const result = await iap.queryPurchases(this.context, {
        productType: iap.ProductType.CONSUMABLE,
        queryType: iap.PurchaseQueryType.UNFINISHED
      });
      for (const purchaseData of result.purchaseDataList || []) {
        await this.deliverAndFinish(purchaseData, false);
      }
    } catch (e) {
      console.warn('恢复未完成订单失败:', e);
    }
  }

  async deliverAndFinish(purchaseData: string, showResult: boolean = true): Promise<void> {
    const result: IapCreditResponse =
      await HuaweiAccountService.creditIapPurchase(this.context, purchaseData);
    await iap.finishPurchase(this.context, {
      productType: iap.ProductType.CONSUMABLE,
      purchaseToken: result.purchaseToken,
      purchaseOrderId: result.purchaseOrderId
    });
    if (showResult) {
      const debtMessage = result.debtOffsetPoints > 0 ?
        `，其中 ${result.debtOffsetPoints} 点用于抵扣退款欠款` : '';
      HdsFeedback.showToast(`充值成功，已到账 ${result.creditedPoints} 点${debtMessage}`);
    }
  }

  errorMessage(error: Object, fallback: string): string {
    const apiError = error as AccountApiError;
    if (apiError?.message) {
      return apiError.message;
    }
    return fallback;
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  // ---- 会员 ----

  isSuperMember(): boolean {
    return this.membershipSku === 'SUPER_LIFETIME';
  }

  selectedProduct(): MembershipProduct | undefined {
    return this.memberProducts.find((item: MembershipProduct) => item.sku === this.selectedSku);
  }

  /** 客户端预判明显不能购买的档位；最终以服务端报价为准。 */
  purchaseBlockReason(product: MembershipProduct): string {
    const state = this.membership.active ? this.membership.state : null;
    if (!state || state.expiresAt !== null) return '';
    if (state.sku === 'SUPER_LIFETIME') return '已是最高档位';
    return product.sku === 'SUPER_LIFETIME' ? '' : '已拥有终身权益';
  }

  /** 当前档位还能买的方案：终身会员只剩超级会员升级，终身超级会员没有。 */
  purchasableProducts(): MembershipProduct[] {
    return this.memberProducts.filter((item: MembershipProduct) => this.purchaseBlockReason(item) === '');
  }

  showPurchaseBar(): boolean {
    return !this.editingProfile && this.purchasableProducts().length > 0;
  }

  purchaseLabel(): string {
    if (this.memberBusy) return '正在处理…';
    if (!this.accountLoggedIn) return '登录后开通会员';
    const product = this.selectedProduct();
    if (!product) return '请选择会员方案';
    if (!product.salesEnabled) {
      return this.opensLater(product) ? `${this.formatDateTime(product.salesStartsAt!)} 开放订购` : '暂未开放购买';
    }
    const blocked = this.purchaseBlockReason(product);
    if (blocked) return blocked;
    if (!this.agreed) return '请先阅读并勾选购买说明';
    const current = this.membership.active ? this.membership.state : null;
    if (current && product.months === null) return `升级为${product.name}`;
    if (current) return `续费${product.name}`;
    return `使用 ${this.priceOf(product)} 充值点开通`;
  }

  /** 当前实际扣点；旧服务端没有 pricePoints 时用原价。 */
  priceOf(product: MembershipProduct): number {
    return product.pricePoints > 0 ? product.pricePoints : product.points;
  }

  discounted(product: MembershipProduct): boolean {
    return this.priceOf(product) < product.points;
  }

  /** 方案卡预告开售时可享的活动价；实际购买仍使用服务端报价。 */
  planPriceOf(product: MembershipProduct): number {
    const promotion = product.promotion;
    const opening = product.salesStartsAt;
    if (this.opensLater(product) && promotion && opening !== null &&
      promotion.startsAt <= opening && promotion.endsAt > opening &&
      promotion.pricePoints > 0 && promotion.pricePoints < product.points) {
      return promotion.pricePoints;
    }
    return this.priceOf(product);
  }

  planDiscounted(product: MembershipProduct): boolean {
    return this.planPriceOf(product) < product.points;
  }

  opensLater(product: MembershipProduct): boolean {
    return !product.salesEnabled && product.salesStartsAt !== null && product.salesStartsAt > Date.now();
  }

  /** 活动结束时间是次日零点，展示为最后一天。 */
  promotionLastDay(promotion: MembershipPromotion): string {
    const last = new Date(promotion.endsAt - 1);
    return `${last.getMonth() + 1}月${last.getDate()}日`;
  }

  formatDateTime(value: number): string {
    const date = new Date(value);
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${date.getMonth() + 1}月${date.getDate()}日 ${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  /** 首发活动横幅：任一档位有进行中或即将开始的活动时显示。 */
  launchBanner(): string {
    // 旧服务端不返回 promotion 字段，解析后是 undefined 而不是 null。
    const promoted = this.purchasableProducts().filter((item: MembershipProduct) => !!item.promotion);
    if (promoted.length === 0) return '';
    const promotion = promoted[0].promotion!;
    const names = promoted.map((item: MembershipProduct) => item.name).join('与');
    const start = new Date(promotion.startsAt);
    const period = `${start.getMonth() + 1}月${start.getDate()}日至${this.promotionLastDay(promotion)}`;
    return `${promotion.label}：${period}，${names}${promotion.pricePoints * 2 === promoted[0].points ? '半价' : '限时优惠'}`;
  }

  purchaseEnabled(): boolean {
    if (this.memberBusy) return false;
    if (!this.accountLoggedIn) return true;
    const product = this.selectedProduct();
    return !!product && product.salesEnabled && this.agreed && this.purchaseBlockReason(product) === '';
  }

  purchaseTerms(): string {
    return '1. 会员使用充值点开通，赠送点不可抵扣，不自动续费；确认前会显示服务端报价和实际扣点。\n' +
      '2. 月度、年度会员可叠加续费，有效期顺延；终身会员不重复购买，可补差价升级为终身超级会员。定期会员升级终身时，按尚未使用的时长折算抵扣，抵扣不退回、不提现。\n' +
      '3. 会员主题包含现有及以后加入会员主题库的主题，单独售卖的主题除外；已单独购买的主题保留原有效期。\n' +
      '4. 月度会员不含每月朗读礼包。年度会员每月标准 5000 字或精品 2500 字，终身会员 8000/4000 字，终身超级会员 12000/6000 字。按北京时间自然月（每月1日至月末）领取，每个账号每月标准或精品二选一，升级或重新开通不重复领取，未领不补发。领取时须有有效的年度或终身权益；年度会员用月度续费延长的时段不含礼包。已领字数可累计，在连续会员期内有效，到期后重新开通不恢复旧周期额度。\n' +
      '5. 终身超级会员的云空间为书籍、字体与书源共用 1GB。下载额度按北京时间自然月计算，每月 1GB，每月1日零点重置，未用额度不结转。\n' +
      '6. 发生内购退款形成欠款时，会员权益暂停，补齐后恢复。';
  }

  async showPurchaseTerms(): Promise<void> {
    try {
      await promptAction.showDialog({ title: '会员权益与购买说明', message: this.purchaseTerms(),
        buttons: [{ text: '我知道了', color: this.accentColor() }] });
    } catch (e) {
      // Dismissing the explanation never changes purchase consent.
    }
  }

  async buyMembership(): Promise<void> {
    if (!this.accountLoggedIn) {
      this.login();
      return;
    }
    const product = this.selectedProduct();
    if (this.memberBusy || !this.agreed || !product || !product.salesEnabled ||
      this.purchaseBlockReason(product) !== '') {
      return;
    }
    this.memberBusy = true;
    try {
      const purchaseUserId = AccountSessionStore.account().userId;
      const quote = await AccountCommerceApi.quoteMembership(product.sku, AccountSessionStore.token());
      if (quote.payablePoints > this.paidPoints) {
        // 充值入口收进了点数行的面板，点数不够时在这里直接引导过去。
        const recharge = await promptAction.showDialog({
          title: '充值点不足',
          message: `本次需扣除 ${quote.payablePoints} 充值点，当前 ${this.paidPoints} 点，还差 ` +
            `${quote.payablePoints - this.paidPoints} 点。赠送点不可抵扣。`,
          buttons: [{ text: '取消', color: this.subTextColor() }, { text: '去充值', color: this.accentColor() }]
        });
        if (recharge.index === 1) this.showRechargeSheet = true;
        return;
      }
      const credit = quote.creditPoints > 0 ? `\n升级抵扣 ${quote.creditPoints} 点` : '';
      const decision = await promptAction.showDialog({
        title: this.membership.active ? `确认${product.months === null ? '升级' : '续费'}` : `开通${product.name}`,
        message: `${product.name}  ${quote.listPoints} 点${credit}\n本次扣除 ${quote.payablePoints} 充值点\n` +
          `当前充值点 ${this.paidPoints}\n赠送点不可抵扣，不自动续费。`,
        buttons: [{ text: '取消', color: this.subTextColor() },
          { text: '确认扣点', color: MembershipIcons.accent(product.sku, this.appDarkMode) }]
      });
      if (decision.index !== 1) return;
      await MembershipCommerceService.purchase(this.context, quote.quoteId, purchaseUserId);
      this.membership = AccountSessionStore.account().membership || new MembershipSnapshot();
      // 升级为终身超级会员后立即开始云端书籍与字体同步。
      CloudAutoSync.schedule(this.context, 0);
      this.agreed = false;
      this.orders = [];
      this.ordersExpanded = false;
      HdsFeedback.showToast(`已开通${product.name}`);
    } catch (e) {
      HdsFeedback.showToast(this.errorMessage(e, '购买未完成，请刷新后重试'));
    } finally {
      this.memberBusy = false;
      this.ensureSelectableSku();
    }
  }

  async toggleOrders(): Promise<void> {
    this.ordersExpanded = !this.ordersExpanded;
    if (!this.ordersExpanded) return;
    try {
      this.orders = (await AccountCommerceApi.membershipOrders(AccountSessionStore.token())).orders || [];
    } catch (e) {
      this.ordersExpanded = false;
      HdsFeedback.showToast(this.errorMessage(e, '订单暂时无法加载'));
    }
  }

  memberValidityText(): string {
    if (!this.accountLoggedIn) return '登录后查看会员、点数与主题权益';
    if (this.membership.restricted) return '权益暂停中';
    const state = this.membership.state;
    if (!this.membershipSku || !state) return '开通会员畅享主题库，年度及终身会员每月领朗读礼包';
    if (state.expiresAt === null) return '永久有效';
    return `有效期至 ${this.formatDate(state.expiresAt)} · 不自动续费`;
  }

  formatDate(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
  }

  /** 会员卡上“领取会员权益”入口的提示：本期礼包、专属主题还有没有没领的。 */
  benefitsEntryHint(): string {
    const revision = this.entitlementsRevision;
    const gift = MembershipGiftRules.pending(this.membership, this.membershipSku);
    const theme = revision >= 0 && this.isSuperMember() &&
      !AccountSessionStore.hasOwnedEntitlement(ThemeIds.OBSIDIAN_ARCHIVE);
    if (gift && theme) return '2 项权益待领取';
    if (gift) return '本期礼包待领取';
    if (theme) return '专属主题待领取';
    return '';
  }

  @Builder
  benefitsEntry() {
    Row({ space: AppSpacing.SM }) {
      SymbolGlyph($r('sys.symbol.gift'))
        .fontSize(18)
        .fontColor([MembershipIcons.cardTextColor(this.appDarkMode)])
      Text('领取会员权益')
        .fontSize(AppFontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
        .layoutWeight(1)
      if (this.benefitsEntryHint()) {
        Text(this.benefitsEntryHint())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
        Circle()
          .width(7)
          .height(7)
          .fill(ThemeRuntime.dangerColor(this.appDarkMode))
      } else {
        Text('查看全部权益')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(MembershipIcons.cardSubTextColor(this.appDarkMode))
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([MembershipIcons.cardSubTextColor(this.appDarkMode)])
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.MD, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(this.appDarkMode ? '#1FFFFFFF' : '#59FFFFFF')
    .onClick(() => {
      router.pushUrl({ url: 'pages/MemberBenefits' });
    })
  }

  @Builder
  memberCard() {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.LG }) {
        if (this.accountLoggedIn && this.avatarUrl) {
          Image(this.avatarUrl)
            .width(60)
            .height(60)
            .borderRadius(30)
            .objectFit(ImageFit.Cover)
            .border({ width: 2, color: '#CCFFFFFF' })
        } else {
          Image($r('app.media.ic_default_reader_avatar'))
            .width(60)
            .height(60)
            .borderRadius(30)
            .objectFit(ImageFit.Cover)
            .border({ width: 2, color: '#CCFFFFFF' })
        }
        Column({ space: AppSpacing.XS }) {
          Row({ space: AppSpacing.SM }) {
            Text(this.accountLoggedIn ? this.displayName : '未登录')
              .fontSize(AppFontSize.TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.membershipSku ? MembershipIcons.nameColor(this.membershipSku, this.appDarkMode) :
                MembershipIcons.cardTextColor(this.appDarkMode))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
            if (this.membershipSku) {
              Image(MembershipIcons.forSku(this.membershipSku))
                .width(28)
                .height(28)
                .objectFit(ImageFit.Contain)
                .flexShrink(0)
            }
          }
          .alignItems(VerticalAlign.Center)
          Text(this.membershipSku ? MembershipIcons.label(this.membershipSku) :
            (this.accountLoggedIn ? '普通用户' : '登录后新用户免费获得 300 点'))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(MembershipIcons.cardSubTextColor(this.appDarkMode))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.accountLoggedIn) {
          Text('编辑资料')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
            .borderRadius(14)
            .backgroundColor(this.appDarkMode ? '#26FFFFFF' : '#66FFFFFF')
            .onClick(() => {
              this.beginEditProfile();
            })
        } else {
          Button(this.loading ? '登录中' : '华为账号登录')
            .height(36)
            .fontSize(AppFontSize.BODY)
            .enabled(!this.loading)
            .backgroundColor(this.accentColor())
            .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
            .onClick(() => {
              this.login();
            })
        }
      }
      .width('100%')

      Column({ space: AppSpacing.XS }) {
        Text(this.membershipSku ? MembershipIcons.label(this.membershipSku) : '轻页会员')
          .fontSize(AppFontSize.HEADLINE)
          .fontWeight(FontWeight.Bold)
          .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
        Text(this.memberValidityText())
          .fontSize(AppFontSize.BODY)
          .fontColor(MembershipIcons.cardSubTextColor(this.appDarkMode))
        Text(this.memberCardBenefits())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(MembershipIcons.cardSubTextColor(this.appDarkMode))
          .margin({ top: AppSpacing.XS })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.accountLoggedIn) {
        Row() {
          this.pointCell(true)
          Divider()
            .vertical(true)
            .height(32)
            .color(this.appDarkMode ? '#33FFFFFF' : '#33000000')
          this.pointCell(false)
          Blank()
          Text('充值')
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XS, bottom: AppSpacing.XS })
            .borderRadius(14)
            .border({ width: 1, color: MembershipIcons.cardSubTextColor(this.appDarkMode) })
            .margin({ right: AppSpacing.MD })
            .onClick(() => {
              this.showRechargeSheet = true;
            })
          Text('?')
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(MembershipIcons.cardSubTextColor(this.appDarkMode))
            .textAlign(TextAlign.Center)
            .width(22)
            .height(22)
            .borderRadius(11)
            .border({ width: 1, color: MembershipIcons.cardSubTextColor(this.appDarkMode) })
            .accessibilityText('点数使用说明')
            .onClick(() => {
              this.showPointsUsageDialog();
            })
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
        .borderRadius(ThemeRuntime.mediumRadius())
        .backgroundColor(this.appDarkMode ? '#1FFFFFFF' : '#59FFFFFF')
        .alignItems(VerticalAlign.Center)
      }
      if (this.accountLoggedIn && this.membershipSku) {
        this.benefitsEntry()
      }
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .linearGradient({ angle: 135, colors: MembershipIcons.cardGradient(this.membershipSku, this.appDarkMode) })
    .shadow({ radius: 12, color: this.appDarkMode ? '#33000000' : '#1A6E5F48', offsetY: 4 })
  }

  // 点数要在 builder 里直接读状态：按值传进 @Builder 的数字不会随充值到账刷新。
  @Builder
  pointCell(paid: boolean) {
    Column({ space: AppSpacing.XXS }) {
      Row({ space: AppSpacing.XS }) {
        Text(`${paid ? this.paidPoints : this.promoPoints}`)
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
        Text(paid ? '充值点' : '赠送点')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(MembershipIcons.cardSubTextColor(this.appDarkMode))
      }
      .alignItems(VerticalAlign.Bottom)
      Text(paid ? '可开通会员' : '可兑换主题')
        .fontSize(AppFontSize.MICRO)
        .fontColor(MembershipIcons.cardSubTextColor(this.appDarkMode))
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ right: AppSpacing.LG, left: paid ? 0 : AppSpacing.LG })
  }

  @Builder
  noticeBanner(message: string) {
    Row({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(18)
        .fontColor([ThemeRuntime.warningColor(this.appDarkMode)])
      Text(message)
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(18)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(this.appDarkMode ? '#332A1A' : '#FFF4E3')
  }

  // 标题在这里按状态算：按值传进 @Builder 的字符串在开通或升级后不会刷新。
  @Builder
  planSectionHeader() {
    Row() {
      Text(this.membershipSku === 'LIFETIME' ? '升级超级会员' :
        (this.membership.active ? '续费与升级' : '会员方案'))
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Text('购买说明')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .onClick(() => {
          this.showPurchaseTerms();
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
  }

  @Builder
  planSection() {
    Column({ space: AppSpacing.MD }) {
      this.planSectionHeader()
      if (this.launchBanner()) {
        Row({ space: AppSpacing.SM }) {
          SymbolGlyph($r('sys.symbol.timer'))
            .fontSize(16)
            .fontColor([MembershipIcons.accent('LIFETIME', this.appDarkMode)])
          Text(this.launchBanner())
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
        .borderRadius(ThemeRuntime.mediumRadius())
        .linearGradient({ angle: 90, colors: MembershipIcons.cardGradient('LIFETIME', this.appDarkMode) })
      }
      Scroll() {
        Row({ space: AppSpacing.MD }) {
          ForEach(this.purchasableProducts(), (product: MembershipProduct) => {
            this.planCard(product)
          }, (product: MembershipProduct) =>
            `${product.sku}_${product.salesEnabled}_${this.planPriceOf(product)}_${product.promotion?.startsAt ?? 0}`)
        }
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.SM, bottom: AppSpacing.SM })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      Text(this.membershipSku === 'LIFETIME' ? '补差价升级为终身超级会员，扣点前会显示服务端报价。' :
        this.membership.active ?
        '定期会员续费顺延有效期；升级终身按未使用时长折算抵扣。扣点前会显示服务端报价。' :
        '仅限充值点，不自动续费。终身会员可补差价升级为终身超级会员。')
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(18)
        .fontColor(this.subTextColor())
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    }
    .width('100%')
  }

  @Builder
  planCard(product: MembershipProduct) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: AppSpacing.XS }) {
        Image(MembershipIcons.forSku(product.sku))
          .width(64)
          .height(64)
          .objectFit(ImageFit.Contain)
          .margin({ bottom: AppSpacing.XS })
        Text(product.name)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
        Row({ space: AppSpacing.XXS }) {
          Text(`${this.planPriceOf(product)}`)
            .fontSize(AppFontSize.DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.planDiscounted(product) ? MembershipIcons.accent(product.sku, this.appDarkMode) :
              this.primaryTextColor())
          Text('点')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .margin({ bottom: 5 })
        }
        .alignItems(VerticalAlign.Bottom)
        Row({ space: AppSpacing.XS }) {
          if (this.planDiscounted(product)) {
            Text(this.opensLater(product) ? '首发预告价' : '活动价')
              .fontSize(AppFontSize.MICRO)
              .fontColor(MembershipIcons.accent(product.sku, this.appDarkMode))
            Text(`${product.points} 点`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .decoration({ type: TextDecorationType.LineThrough, color: this.subTextColor() })
          }
        }
        .height(18)
        Text(this.planSubtitle(product))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: AppSpacing.XL, bottom: AppSpacing.XL, left: AppSpacing.MD, right: AppSpacing.MD })

      if (this.planBadge(product)) {
        Text(this.planBadge(product))
          .fontSize(AppFontSize.MICRO)
          .fontWeight(FontWeight.Medium)
          .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
          .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
          .borderRadius({ topRight: ThemeRuntime.largeRadius(), bottomLeft: ThemeRuntime.largeRadius() })
          .linearGradient({ angle: 135, colors: MembershipIcons.cardGradient(product.sku, this.appDarkMode) })
      }
    }
    .width(140)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(product.sku === this.selectedSku ?
      (this.appDarkMode ? '#1AFFFFFF' : '#FFFFFF') : this.cardColor())
    .border({
      width: product.sku === this.selectedSku ? 2 : 1,
      color: product.sku === this.selectedSku ? MembershipIcons.accent(product.sku, this.appDarkMode) :
        this.dividerColor()
    })
    .opacity(product.salesEnabled && this.purchaseBlockReason(product) === '' ? 1 : 0.55)
    .accessibilityText(`${product.name}，${this.planDiscounted(product) ?
      (this.opensLater(product) ? '首发预告价' : '活动价') : ''}${this.planPriceOf(product)} 点，` +
      `${this.planDiscounted(product) ? '原价' + product.points + '点，' : ''}${this.planSubtitle(product)}`)
    .onClick(() => {
      if (!this.memberBusy) this.selectedSku = product.sku;
    })
  }

  planSubtitle(product: MembershipProduct): string {
    const promotion = product.promotion;
    if (this.opensLater(product)) {
      const start = new Date(product.salesStartsAt!);
      const opening = `${start.getMonth() + 1}月${start.getDate()}日开放`;
      return promotion ? `${opening} · ${promotion.label}` : opening;
    }
    if (!product.salesEnabled) return '准备中';
    if (promotion && this.discounted(product)) return `${promotion.label} · 至${this.promotionLastDay(promotion)}`;
    if (product.months === null) return '永久有效 · 每月礼包';
    if (product.sku === 'MONTHLY') return '1 个月 · 不含礼包';
    return `${product.months} 个月 · 每月礼包`;
  }

  memberCardBenefits(): string {
    if (!this.membershipSku) return '会员主题库 · 朗读礼包 · 在线朗读优先 · 书源同步';
    const items: string[] = ['会员主题库'];
    if (this.isSuperMember()) items.push('专属主题');
    if (MembershipGiftRules.included(this.membership, this.membershipSku)) items.push('每月朗读礼包');
    items.push('在线朗读优先', '书源同步');
    if (this.isSuperMember()) items.push('1GB 云空间');
    return items.join(' · ');
  }

  planBadge(product: MembershipProduct): string {
    if (this.membershipSku === product.sku) return '当前';
    if (product.promotion && (this.discounted(product) || this.opensLater(product))) {
      return product.promotion.pricePoints * 2 === product.points ? '半价' : '优惠';
    }
    if (product.sku === 'ANNUAL' && !this.membershipSku) return '推荐';
    if (product.sku === 'SUPER_LIFETIME') return '云空间';
    return '';
  }

  // 对比表的五列：免费、月度、年度、终身、终身超级。单元格 '✓' 表示包含，'—' 表示没有。
  compareRows(): BenefitCompareRow[] {
    const limits = this.sourceUsage.membershipLimitsEnabled;
    const rows: BenefitCompareRow[] = [
      new BenefitCompareRow('会员主题库', '现有及新增会员主题', ['—', '✓', '✓', '✓', '✓']),
      new BenefitCompareRow('专属主题', '曜金藏书 · 手动领取一年', ['—', '—', '—', '—', '✓']),
      new BenefitCompareRow('每月朗读礼包', '标准 / 精品（字）', ['—', '—', '5000\n2500', '8000\n4000', '12000\n6000']),
      new BenefitCompareRow('在线朗读优先排队', '高峰期优先', ['—', '✓', '✓', '✓', '✓']),
      new BenefitCompareRow('漫画超分', '本机 AI 让低清漫画更清晰', ['—', '✓', '✓', '✓', '✓']),
      new BenefitCompareRow('有效期', '不自动续费', ['—', '1 个月', '12 个月', '永久', '永久'])
    ];
    if (limits) {
      rows.push(new BenefitCompareRow('书源同步数量', '', ['50 个', '500 个', '500 个', '500 个', '不限']));
    }
    rows.push(new BenefitCompareRow('单个书源大小', '云同步上限',
      limits ? ['50KB', '512KB', '512KB', '512KB', '960KB'] : ['512KB', '512KB', '512KB', '512KB', '960KB']));
    rows.push(new BenefitCompareRow('动态头像', 'GIF / WebP 动图', ['—', '—', '—', '✓', '✓']));
    rows.push(new BenefitCompareRow('自定义字体云端同步', '导入即上传，换机可选', ['—', '—', '—', '—', '✓']));
    rows.push(new BenefitCompareRow('本地书籍云端同步', '加入书架即上传', ['—', '—', '—', '—', '✓']));
    rows.push(new BenefitCompareRow('云端空间', '书籍、字体与书源共用', ['—', '—', '—', '—', '1GB']));
    rows.push(new BenefitCompareRow('每月下载额度', '云空间下载', ['—', '—', '—', '—', '1GB']));
    return rows;
  }

  compareColumnForSku(sku: string): number {
    const index = MembershipIcons.SKUS.indexOf(sku);
    return index < 0 ? 0 : index + 1;
  }

  compareColumnSku(column: number): string {
    return column > 0 ? MembershipIcons.SKUS[column - 1] : '';
  }

  compareColumnTitle(column: number): string {
    return ['免费', '月度', '年度', '终身', '终身超级'][column];
  }

  compareHeadline(): string {
    const selected = this.compareColumnForSku(this.selectedSku);
    const current = this.compareColumnForSku(this.membershipSku);
    const selectedLabel = MembershipIcons.label(this.selectedSku) || '会员';
    if (current > 0 && selected === current) return `你正在享有的${MembershipIcons.label(this.membershipSku)}权益`;
    if (selected < current) return `当前${MembershipIcons.label(this.membershipSku)}已包含${selectedLabel}的全部权益`;
    return current > 0 ? `升级为${selectedLabel}，将新增或提升` : `开通${selectedLabel}，即可获得`;
  }

  /** 选中档位相对当前档位多出来的权益；同档时列出当前享有的全部权益。 */
  compareHighlights(): string[] {
    const selected = this.compareColumnForSku(this.selectedSku);
    const current = this.compareColumnForSku(this.membershipSku);
    if (selected < current) return [];
    const result: string[] = [];
    for (const row of this.compareRows()) {
      const value = row.values[selected];
      if (value === '—' || (selected !== current && value === row.values[current])) continue;
      result.push(value === '✓' ? row.title : `${row.title} ${value.replace('\n', '/')}`);
    }
    return result;
  }

  /** 选中档位的列滑出可视区时，把它滑回来并多露出半列，看得出两边还有内容。 */
  revealSelectedCompareColumn(): void {
    if (this.compareViewportWidth <= 0) return;
    const width = this.compareColumnWidth;
    const left = this.compareColumnForSku(this.selectedSku) * width;
    const offset = this.compareScroller.currentOffset().xOffset;
    let target = offset;
    if (left < offset) {
      target = left - width / 2;
    } else if (left + width > offset + this.compareViewportWidth) {
      target = left + width * 1.5 - this.compareViewportWidth;
    }
    target = Math.max(0, Math.min(target, width * 5 - this.compareViewportWidth));
    if (target !== offset) {
      this.compareScroller.scrollTo({ xOffset: target, yOffset: 0, animation: { duration: 260, curve: Curve.EaseOut } });
    }
  }

  compareColumnTint(column: number): string {
    if (column !== this.compareColumnForSku(this.selectedSku)) return '#00000000';
    const accent = MembershipIcons.accent(this.compareColumnSku(column), this.appDarkMode);
    return (this.appDarkMode ? '#33' : '#1F') + accent.substring(1);
  }

  @Builder
  compareEntry() {
    Column() {
      this.serviceRow($r('sys.symbol.list_bullet'), '权益对比', '查看各档会员权益', false, () => {
        this.compareExpanded = true;
      })
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  @Builder
  benefitsCard() {
    Column({ space: AppSpacing.LG }) {
      Row() {
        Text('权益对比')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        if (this.isSuperMember()) {
          Text('收起')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.accentColor())
            .onClick(() => {
              this.compareExpanded = false;
            })
        } else {
          Text('左右滑动 · 点按列切换方案')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
      }
      .width('100%')

      this.compareHighlightPanel()

      Row() {
        Column() {
          Column()
            .height(this.compareHeaderHeight)
          ForEach(this.compareRows(), (row: BenefitCompareRow) => {
            Column({ space: 2 }) {
              Text(row.title)
                .fontSize(AppFontSize.CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.primaryTextColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (row.note) {
                Text(row.note)
                  .fontSize(AppFontSize.MICRO)
                  .fontColor(this.subTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .height(this.compareRowHeight)
            .padding({ right: AppSpacing.SM })
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
            .border({ width: { top: 0.5 }, color: this.dividerColor() })
          }, (row: BenefitCompareRow) => row.title)
        }
        .width(this.compareTitleWidth)

        Scroll(this.compareScroller) {
          Column() {
            Row() {
              ForEach([0, 1, 2, 3, 4], (column: number) => {
                this.compareHeaderCell(column)
              }, (column: number) => `head_${column}`)
            }
            ForEach(this.compareRows(), (row: BenefitCompareRow, index: number) => {
              Row() {
                ForEach([0, 1, 2, 3, 4], (column: number) => {
                  this.compareValueCell(row, column, index === this.compareRows().length - 1)
                }, (column: number) => `${row.title}_${column}`)
              }
              .border({ width: { top: 0.5 }, color: this.dividerColor() })
            }, (row: BenefitCompareRow) => row.title + row.values.join('|'))
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .onAreaChange((_old: Area, area: Area) => {
          this.compareViewportWidth = Number(area.width);
          // 每列约 96vp：放得下五列就平分不滑动；放不下就显示能放下的整列再多露半列，提示可以滑动。
          const fit = Math.floor(this.compareViewportWidth / 96);
          this.compareColumnWidth = fit >= 5 ? this.compareViewportWidth / 5 :
            this.compareViewportWidth / (Math.max(2, fit) + 0.5);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Text('超级会员的书源与云文件共用 1GB；单个书源 960KB 为技术上限。单独售卖的主题不在会员主题库内。')
        .fontSize(AppFontSize.MICRO)
        .lineHeight(15)
        .fontColor(this.subTextColor())
        .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  compareHighlightPanel() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        Image(MembershipIcons.forSku(this.selectedSku))
          .width(36)
          .height(36)
          .objectFit(ImageFit.Contain)
        Text(this.compareHeadline())
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
          .layoutWeight(1)
      }
      .width('100%')
      if (this.compareHighlights().length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.compareHighlights(), (item: string) => {
            Row({ space: AppSpacing.XS }) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(12)
                .fontColor([MembershipIcons.nameColor(this.selectedSku, this.appDarkMode)])
              Text(item)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
            }
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
            .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
            .borderRadius(12)
            .backgroundColor(this.appDarkMode ? '#26FFFFFF' : '#8CFFFFFF')
          }, (item: string) => item)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.largeRadius())
    .linearGradient({ angle: 135, colors: MembershipIcons.cardGradient(this.selectedSku, this.appDarkMode) })
  }

  @Builder
  compareHeaderCell(column: number) {
    Column({ space: AppSpacing.XXS }) {
      if (column === 0) {
        SymbolGlyph($r('sys.symbol.person'))
          .fontSize(24)
          .fontColor([this.subTextColor()])
          .height(36)
      } else {
        Image(MembershipIcons.forSku(this.compareColumnSku(column)))
          .width(36)
          .height(36)
          .objectFit(ImageFit.Contain)
      }
      Text(this.compareColumnTitle(column))
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor(column === 0 ? this.subTextColor() :
          MembershipIcons.nameColor(this.compareColumnSku(column), this.appDarkMode))
        .maxLines(1)
      Text(this.compareColumnForSku(this.membershipSku) === column && (column > 0 || this.accountLoggedIn) ?
        '当前' : ' ')
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
    }
    .width(this.compareColumnWidth)
    .height(this.compareHeaderHeight)
    .justifyContent(FlexAlign.End)
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.XS })
    .backgroundColor(this.compareColumnTint(column))
    .borderRadius({ topLeft: ThemeRuntime.mediumRadius(), topRight: ThemeRuntime.mediumRadius() })
    .onClick(() => {
      if (column > 0 && !this.memberBusy) this.selectedSku = this.compareColumnSku(column);
    })
  }

  @Builder
  compareValueCell(row: BenefitCompareRow, column: number, last: boolean) {
    Column() {
      if (row.values[column] === '✓') {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([MembershipIcons.nameColor(this.compareColumnSku(column), this.appDarkMode)])
      } else {
        Text(row.values[column])
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(row.values[column] !== '—' && column === this.compareColumnForSku(this.selectedSku) ?
            FontWeight.Bold : FontWeight.Normal)
          .fontColor(row.values[column] === '—' ? this.subTextColor() :
            // 比左边一档多出或提升的权益用该档颜色标出。
            (column >= 2 && row.values[column] !== row.values[column - 1] ?
              MembershipIcons.nameColor(this.compareColumnSku(column), this.appDarkMode) : this.primaryTextColor()))
          .textAlign(TextAlign.Center)
          .maxLines(2)
      }
    }
    .width(this.compareColumnWidth)
    .height(this.compareRowHeight)
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.compareColumnTint(column))
    .borderRadius(last ? { bottomLeft: ThemeRuntime.mediumRadius(), bottomRight: ThemeRuntime.mediumRadius() } : 0)
    .onClick(() => {
      if (column > 0 && !this.memberBusy) this.selectedSku = this.compareColumnSku(column);
    })
  }

  @Builder
  serviceRow(icon: Resource, title: string, detail: string, showDivider: boolean, onClick: () => void) {
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
          if (detail) {
            Text(detail)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
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
    .onClick(onClick)
  }

  @Builder
  serviceList() {
    Column() {
      this.serviceRow($r('sys.symbol.doc_text'), '会员订单', this.ordersExpanded ? '收起' : '最近 50 笔会员订单',
        !this.ordersExpanded, () => {
          this.toggleOrders();
        })
      if (this.ordersExpanded) {
        Column({ space: AppSpacing.MD }) {
          if (this.orders.length === 0) {
            Text('暂无会员订单')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
          }
          ForEach(this.orders, (order: MembershipOrder) => {
            Row({ space: AppSpacing.LG }) {
              Image(MembershipIcons.forSku(order.sku))
                .width(32)
                .height(32)
                .objectFit(ImageFit.Contain)
              Column({ space: AppSpacing.XXS }) {
                Text(MembershipIcons.label(order.sku) || '会员订单')
                  .fontSize(AppFontSize.BODY)
                  .fontColor(this.primaryTextColor())
                Text(this.formatDate(Number(order.createdAt)) +
                  (Number(order.creditPoints) > 0 ? ` · 抵扣 ${order.creditPoints} 点` : ''))
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(this.subTextColor())
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Text(`-${order.pointsSpent} 点`)
                .fontSize(AppFontSize.BODY)
                .fontColor(this.primaryTextColor())
            }
            .width('100%')
          }, (order: MembershipOrder) => order.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 56, right: AppSpacing.XL, bottom: AppSpacing.LG })
        Divider()
          .strokeWidth(0.5)
          .color(this.dividerColor())
          .margin({ left: 56, right: AppSpacing.XL })
      }
      this.serviceRow($r('sys.symbol.info_circle'), '会员权益与购买说明', '开通、续费、礼包与云空间规则', false, () => {
        this.showPurchaseTerms();
      })
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  @Builder
  purchaseBar() {
    Column({ space: AppSpacing.MD }) {
      if (this.accountLoggedIn) {
        Row({ space: AppSpacing.SM }) {
          Checkbox({ name: 'membership-agreement' })
            .select(this.agreed)
            .selectedColor(MembershipIcons.accent(this.selectedSku, this.appDarkMode))
            .width(20)
            .height(20)
            .margin(0)
            .enabled(!this.memberBusy)
            .accessibilityText('同意会员权益与购买说明')
            .onChange((checked: boolean) => {
              this.agreed = checked;
            })
          Text() {
            Span('我已阅读并同意')
              .fontColor(this.subTextColor())
            Span('《会员权益与购买说明》')
              .fontColor(this.accentColor())
              .onClick(() => {
                this.showPurchaseTerms();
              })
          }
          .fontSize(AppFontSize.CAPTION)
          .layoutWeight(1)
        }
        .width('100%')
      }
      Text(this.purchaseLabel())
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(48)
        .borderRadius(24)
        .linearGradient({ angle: 90, colors: MembershipIcons.cardGradient(this.selectedSku, this.appDarkMode) })
        .opacity(this.purchaseEnabled() ? 1 : 0.5)
        .onClick(() => {
          if (this.purchaseEnabled()) this.buyMembership();
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG,
      bottom: AppSpacing.LG + this.navBarHeight })
    .backgroundColor(this.cardColor())
    .borderRadius({ topLeft: ThemeRuntime.cardRadius(), topRight: ThemeRuntime.cardRadius() })
    .shadow({ radius: 16, color: this.appDarkMode ? '#66000000' : '#1A000000', offsetY: -2 })
  }

  @Builder
  avatarCropper() {
    Column({ space: AppSpacing.LG }) {
      Text('裁剪头像')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text('拖动图片调整位置，使用下方滑块缩放。圆形区域是头像最终显示范围。')
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(18)
        .fontColor(this.subTextColor())
        .width('100%')
      Stack({ alignContent: Alignment.Center }) {
        Image(this.cropSourceUri)
          .width(this.cropPreviewWidth())
          .height(this.cropPreviewHeight())
          .objectFit(ImageFit.Fill)
          .translate({
            x: -this.cropOffsetX * this.cropMaxTranslateX(),
            y: -this.cropOffsetY * this.cropMaxTranslateY()
          })
        Row()
          .width(this.cropBoxSize)
          .height(this.cropBoxSize)
          .borderRadius(this.cropBoxSize / 2)
          .border({ width: 3, color: '#FFFFFFFF' })
          .shadow({ radius: 3, color: '#99000000' })
          .hitTestBehavior(HitTestMode.None)
      }
      .width(this.cropBoxSize)
      .height(this.cropBoxSize)
      .clip(true)
      .borderRadius(14)
      .backgroundColor('#FF111111')
      .priorityGesture(
        PanGesture({ direction: PanDirection.All, distance: 1 })
          .onActionStart((_event: GestureEvent) => {
            this.startCropPan();
          })
          .onActionUpdate((event: GestureEvent) => {
            this.updateCropPan(event);
          }),
        GestureMask.IgnoreInternal
      )
      Row({ space: AppSpacing.MD }) {
        Text('缩放')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
        Slider({ value: this.cropZoom, min: 1, max: 4, step: 0.05 })
          .layoutWeight(1)
          .showTips(true)
          .selectedColor(this.accentColor())
          .trackColor(this.dividerColor())
          .onChange((value: number) => {
            this.cropZoom = value;
          })
        Text(`${this.cropZoom.toFixed(1)}×`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width(36)
      }
      .width('100%')
      Row({ space: AppSpacing.MD }) {
        Button('重新选择')
          .layoutWeight(1)
          .height(40)
          .fontColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .enabled(!this.processingCrop)
          .onClick(() => {
            this.croppingAvatar = false;
            this.pickProfileAvatar();
          })
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .enabled(!this.processingCrop)
          .onClick(() => {
            this.cancelAvatarCrop();
          })
        Button(this.processingCrop ? '处理中' : '确认裁剪')
          .layoutWeight(1.35)
          .height(40)
          .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
          .backgroundColor(this.accentColor())
          .enabled(!this.processingCrop)
          .onClick(() => {
            this.confirmAvatarCrop();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  profileEditor() {
    Column({ space: AppSpacing.LG }) {
      Text('编辑个人资料')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Row({ space: AppSpacing.LG }) {
        if (this.profileAvatarPixelMap) {
          Image(this.profileAvatarPixelMap)
            .width(64)
            .height(64)
            .borderRadius(32)
            .objectFit(ImageFit.Cover)
        } else if (this.profileAvatarPreview && this.profileAvatarCrop) {
          Stack({ alignContent: Alignment.TopStart }) {
            Image(this.profileAvatarPreview)
              .width(this.profileAvatarSourceWidth * 64 / this.profileAvatarCrop.size)
              .height(this.profileAvatarSourceHeight * 64 / this.profileAvatarCrop.size)
              .objectFit(ImageFit.Fill)
              .translate({ x: -this.profileAvatarCrop.left * 64 / this.profileAvatarCrop.size,
                y: -this.profileAvatarCrop.top * 64 / this.profileAvatarCrop.size })
          }
          .width(64)
          .height(64)
          .borderRadius(32)
          .clip(true)
        } else if (this.profileAvatarPreview) {
          Image(this.profileAvatarPreview)
            .width(64)
            .height(64)
            .borderRadius(32)
            .objectFit(ImageFit.Cover)
        } else {
          Image($r('app.media.ic_default_reader_avatar'))
            .width(64)
            .height(64)
            .borderRadius(32)
            .objectFit(ImageFit.Cover)
        }
        Column({ space: AppSpacing.MD }) {
          Button('选择头像')
            .height(34)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.accentColor())
            .backgroundColor(this.inputColor())
            .enabled(!this.savingProfile)
            .onClick(() => {
              this.pickProfileAvatar();
            })
          Button('使用默认头像')
            .height(30)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .backgroundColor(Color.Transparent)
            .enabled(!this.savingProfile)
            .onClick(() => {
              this.useDefaultAvatar();
            })
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Text(this.canUseAnimatedAvatar() ? '支持 GIF / WebP 动态头像：2MB 内，最多 120 帧，单帧不超过 1024×1024。'
        : '终身会员和终身超级会员支持 GIF / WebP 动态头像。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      TextInput({ text: this.profileNameInput, placeholder: '请输入昵称' })
        .width('100%')
        .height(44)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .maxLength(30)
        .enabled(!this.savingProfile)
        .onChange((value: string) => {
          this.profileNameInput = value;
        })
      Text('登录时默认使用华为账号的昵称和头像，在这里修改后不会再被覆盖。资料保存在账号服务端并随账号跨设备同步。')
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(17)
        .fontColor(this.subTextColor())
        .width('100%')
      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .enabled(!this.savingProfile)
          .onClick(() => {
            this.cancelEditProfile();
          })
        Button(this.savingProfile ? '保存中' : '保存')
          .layoutWeight(1)
          .height(40)
          .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
          .backgroundColor(this.accentColor())
          .enabled(!this.savingProfile)
          .onClick(() => {
            this.saveProfile();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  pointsUsageDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text('点数使用说明')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text('• 点数分充值点和赠送点：充值点通过内购获得（1 元 = 10 点），赠送点为每个华为账号首次登录赠送 300 点\n' +
        '• 开通、续费或升级会员：仅支持充值点，赠送点不能抵扣\n' +
        '• 兑换精选主题：60 点/个（以主题页标示为准），有效期 365 天，充值点和赠送点均可支付，优先消耗赠送点\n' +
        '• 兑换在线朗读字数包：在“我的-在线朗读”中兑换，仅支持充值点，赠送点不能兑换\n' +
        '• 点数仅限本应用内消费，不支持转让或提现；余额与主题权益跨设备同步')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .lineHeight(22)
        .width('100%')
      Button('我知道了')
        .width('100%')
        .height(42)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.accentColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.buttonRadius())
        .onClick(() => {
          this.closePointsUsageDialog();
        })
    }
    .padding(AppSpacing.XXL)
  }

  showPointsUsageDialog(): void {
    this.pointsUsageDialogBuilder = (): void => {
      this.pointsUsageDialogContent();
    };
    // Dialog APIs moved off UIContext to getPromptAction() in this SDK; the
    // builder overload is what the compatible API level exposes.
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.pointsUsageDialogBuilder,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode)
    }).then((dialogId: number) => {
      this.pointsUsageDialogId = dialogId;
    }).catch((error: Error) => {
      console.warn('显示点数使用说明失败:', error);
    });
  }

  closePointsUsageDialog(): void {
    if (this.pointsUsageDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.pointsUsageDialogId);
      this.pointsUsageDialogId = -1;
    }
  }

  @Builder
  rechargeSheet() {
    Column({ space: AppSpacing.SM }) {
      this.rechargeSection()
      Text(`当前充值点 ${this.paidPoints} · 可开通会员、兑换朗读字数包与主题`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    }
    .width('100%')
    .padding({ bottom: AppSpacing.XL + this.navBarHeight })
  }

  @Builder
  rechargeSection() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Text('充值点数')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text('1 元 = 10 点')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Grid() {
        ForEach(this.products, (product: RechargeProduct) => {
          GridItem() {
            Column({ space: AppSpacing.XS }) {
              Row({ space: AppSpacing.XXS }) {
                Text(`${product.points}`)
                  .fontSize(AppFontSize.HEADLINE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.primaryTextColor())
                Text('点')
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(this.subTextColor())
                  .margin({ bottom: 3 })
              }
              .alignItems(VerticalAlign.Bottom)
              if (this.purchasingProductId === product.productId) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.accentColor())
              } else {
                Text(product.localPrice || `预计 ¥${product.expectedPriceYuan}`)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(this.accentColor())
              }
            }
            .width('100%')
            .height(84)
            .justifyContent(FlexAlign.Center)
            .borderRadius(ThemeRuntime.largeRadius())
            .backgroundColor(this.inputColor())
            .onClick(() => {
              this.buy(product);
            })
          }
        }, (product: RechargeProduct) => product.productId)
      }
      .columnsTemplate(this.rechargeColumnsTemplate())
      .columnsGap(AppSpacing.MD)
      .rowsGap(AppSpacing.MD)
      .width('100%')
      .height(this.rechargeGridHeight())
      .enableScrollInteraction(false)
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  accountActions() {
    Text('退出登录')
      .width('100%')
      .height(48)
      .textAlign(TextAlign.Center)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
      .borderRadius(ThemeRuntime.cardRadius())
      .backgroundColor(this.cardColor())
      .onClick(() => {
        this.logout();
      })
  }

  @Builder
  loginGuide() {
    Column({ space: AppSpacing.MD }) {
      Text('登录后可用')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text('• 每个华为账号首次登录赠送 300 点\n• 点数余额、会员和主题权益可跨终端同步')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .lineHeight(22)
        .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  serviceHint() {
    if (!AccountCommerceConfig.isServerConfigured()) {
      Text('开发配置未完成：请在 AccountCommerceConfig.ets 填写 HTTPS 服务端地址，并在 module.json5 配置 AGC Client ID。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#C05A23')
        .lineHeight(18)
        .width('100%')
        .padding(AppSpacing.LG)
        .borderRadius(ThemeRuntime.mediumRadius())
        .backgroundColor(this.appDarkMode ? '#332216' : '#FFF3E8')
    } else {
      Text('登录和购买表示你同意应用的用户协议、隐私政策与点数服务规则。登录时会获取华为账号的昵称和头像作为默认资料，昵称和头像保存到账号服务端并随账号同步；点数仅用于本应用数字内容，不支持转让或提现。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .lineHeight(17)
        .width('100%')
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    }
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

  rechargeColumnsTemplate(): string {
    return this.viewportWidth > this.viewportHeight ? '1fr 1fr 1fr' : '1fr 1fr';
  }

  rechargeColumnCount(): number {
    return this.viewportWidth > this.viewportHeight ? 3 : 2;
  }

  rechargeRowCount(): number {
    return Math.max(1, Math.ceil(this.products.length / this.rechargeColumnCount()));
  }

  rechargeGridHeight(): number {
    const rows = this.rechargeRowCount();
    return rows * 84 + Math.max(0, rows - 1) * AppSpacing.MD;
  }

  areaDimension(value: Length): number {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : 0;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
