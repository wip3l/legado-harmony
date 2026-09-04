import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { iap } from '@kit.IAPKit';
import { util } from '@kit.ArkTS';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { AccountCommerceConfig } from '../account/AccountCommerceConfig';
import {
  AccountApiError,
  IapCreditResponse,
  RechargeProduct
} from '../account/AccountCommerceModels';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { CloudSyncSettingsStore } from '../account/CloudSyncSettingsStore';
import { HuaweiAccountService } from '../account/HuaweiAccountService';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct AccountCenterPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('accountLoggedIn') accountLoggedIn: boolean = false;
  @StorageLink('accountDisplayName') displayName: string = '';
  @StorageLink('accountAvatarUrl') avatarUrl: string = '';
  @StorageLink('accountPoints') points: number = 0;
  @StorageLink('accountPaidPoints') paidPoints: number = 0;
  @StorageLink('accountPromoPoints') promoPoints: number = 0;
  @StorageLink('accountEntitlementsRevision') entitlementsRevision: number = 0;
  @StorageLink('cloudSyncEnabled') cloudSyncEnabled: boolean = false;
  @StorageLink('cloudSyncLastSuccessAt') cloudSyncLastSuccessAt: number = 0;
  @StorageLink('cloudSyncPendingCount') cloudSyncPendingCount: number = 0;
  @StorageLink('cloudSyncStatus') cloudSyncStatus: string = CloudSyncSettingsStore.STATUS_DISABLED;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State loading: boolean = false;
  @State purchasingProductId: string = '';
  @State products: RechargeProduct[] = AccountCommerceConfig.rechargeProducts();
  @State editingProfile: boolean = false;
  @State profileNameInput: string = '';
  @State profileAvatarPreview: string = '';
  @State profileAvatarPixelMap: image.PixelMap | null = null;
  @State profileAvatarBase64: string = '';
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
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.initialize();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: 14 }) {
          if (!this.editingProfile) {
            this.accountCard()
            this.cloudSyncCard()
          }
          if (this.accountLoggedIn) {
            if (this.editingProfile) {
              if (this.croppingAvatar) {
                this.avatarCropper()
              } else {
                this.profileEditor()
              }
            }
            this.pointsCard()
            this.rechargeSection()
            this.accountActions()
          } else {
            this.loginGuide()
          }
          this.serviceHint()
        }
        .width('100%')
        .padding({
          left: 14,
          right: 14,
          top: 70 + this.statusBarHeight,
          bottom: 32 + this.navBarHeight
        })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)

      this.titleBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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

  async initialize(): Promise<void> {
    try {
      await HuaweiAccountService.initialize(this.context);
      if (AccountSessionStore.isLoggedIn() && AccountCommerceConfig.isServerConfigured()) {
        await HuaweiAccountService.refresh(this.context);
        await this.loadIapProducts();
        await this.recoverUnfinishedPurchases();
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
      promptAction.showToast({ message: '请先配置账号服务端地址' });
      return;
    }
    this.loading = true;
    try {
      await HuaweiAccountService.login(this.context);
      promptAction.showToast({ message: '登录成功，账号点数和主题权益已同步' });
      await this.loadIapProducts();
      await this.recoverUnfinishedPurchases();
    } catch (e) {
      const error = e as BusinessError;
      if (error.code !== 1001502005) {
        promptAction.showToast({ message: this.errorMessage(e, '华为账号登录失败') });
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
      await HuaweiAccountService.refresh(this.context);
      promptAction.showToast({ message: '账号数据已同步' });
    } catch (e) {
      promptAction.showToast({ message: this.errorMessage(e, '同步失败') });
    } finally {
      this.loading = false;
    }
  }

  async logout(): Promise<void> {
    const result = await promptAction.showDialog({
      title: '退出登录',
      message: '点数和主题权益仍保存在云端，下次登录后会自动恢复。',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '退出', color: '#E5484D' }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    await HuaweiAccountService.logout(this.context);
    this.editingProfile = false;
    promptAction.showToast({ message: '已退出登录' });
  }

  beginEditProfile(): void {
    this.releaseProfileAvatarPreview();
    this.profileNameInput = this.displayName || '华为用户';
    this.profileAvatarPreview = this.avatarUrl;
    this.profileAvatarBase64 = '';
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
      this.cropSourceUri = uri;
      this.cropSourceWidth = info.size.width;
      this.cropSourceHeight = info.size.height;
      this.cropZoom = 1;
      this.cropOffsetX = 0;
      this.cropOffsetY = 0;
      this.croppingAvatar = true;
    } catch (e) {
      console.error('选择账号头像失败:', e);
      promptAction.showToast({ message: '头像读取失败，请换一张图片重试' });
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
      pixelMap = null;
      this.profileAvatarPreview = '';
      this.removeProfileAvatar = false;
      this.croppingAvatar = false;
      this.cropSourceUri = '';
      promptAction.showToast({ message: '头像裁剪完成' });
    } catch (e) {
      console.error('裁剪账号头像失败:', e);
      promptAction.showToast({ message: '头像裁剪失败，请换一张图片重试' });
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
    this.removeProfileAvatar = true;
  }

  async saveProfile(): Promise<void> {
    if (this.savingProfile) {
      return;
    }
    const displayName = this.profileNameInput.trim();
    if (!displayName || displayName.length > 30) {
      promptAction.showToast({ message: '昵称应为 1 至 30 个字符' });
      return;
    }
    this.savingProfile = true;
    try {
      await HuaweiAccountService.updateProfile(
        this.context, displayName, this.profileAvatarBase64, this.removeProfileAvatar);
      this.editingProfile = false;
      this.profileAvatarBase64 = '';
      this.releaseProfileAvatarPreview();
      promptAction.showToast({ message: '个人资料已保存，并会随账号跨设备同步' });
    } catch (e) {
      promptAction.showToast({ message: this.errorMessage(e, '个人资料保存失败') });
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
      promptAction.showToast({ message: '请先登录华为账号' });
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
        promptAction.showToast({ message: this.errorMessage(e, '支付未完成') });
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
      promptAction.showToast({ message: `充值成功，已到账 ${result.creditedPoints} 点${debtMessage}` });
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

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('账号与点数')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      if (this.accountLoggedIn) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(21)
          .fontColor([this.accentColor()])
          .width(48)
          .height(48)
          .onClick(() => {
            this.refreshAccount();
          })
      } else {
        Blank().width(48)
      }
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ top: this.statusBarHeight })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
  }

  @Builder
  accountCard() {
    Row({ space: 14 }) {
      if (this.accountLoggedIn && this.avatarUrl) {
        Image(this.avatarUrl)
          .width(56)
          .height(56)
          .borderRadius(28)
          .objectFit(ImageFit.Cover)
      } else if (!this.accountLoggedIn) {
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
          .fontSize(56)
          .fontColor([this.accentColor()])
          .width(56)
          .height(56)
      } else {
        Image($r('app.media.ic_default_reader_avatar'))
          .width(56)
          .height(56)
          .borderRadius(28)
          .objectFit(ImageFit.Cover)
      }
      Column({ space: 5 }) {
        Text(this.accountLoggedIn ? this.displayName : '未登录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        if (!this.accountLoggedIn) {
          Text('登录后新用户免费获得 300 点')
            .fontSize(12)
            .fontColor(this.subTextColor())
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.accountLoggedIn) {
        Button('编辑')
          .height(34)
          .fontSize(13)
          .fontColor(this.accentColor())
          .backgroundColor(this.inputColor())
          .onClick(() => {
            this.beginEditProfile();
          })
      } else {
        Button(this.loading ? '登录中' : '华为账号登录')
          .height(38)
          .fontSize(13)
          .enabled(!this.loading)
          .backgroundColor(this.accentColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.login();
          })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.cardColor())
  }

  @Builder
  cloudSyncCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(24)
        .fontColor([this.accentColor()])
        .width(32)

      Column({ space: 4 }) {
        Text('数据同步')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Text(CloudSyncSettingsStore.statusSummary(this.accountLoggedIn, this.cloudSyncEnabled,
          this.cloudSyncStatus, this.cloudSyncPendingCount, this.cloudSyncLastSuccessAt))
          .fontSize(12)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.cardColor())
    .onClick(() => {
      router.pushUrl({ url: 'pages/DataSync' });
    })
  }

  @Builder
  avatarCropper() {
    Column({ space: 14 }) {
      Text('裁剪头像')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text('拖动图片调整位置，使用下方滑块缩放。圆形区域是头像最终显示范围。')
        .fontSize(12)
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
      Row({ space: 10 }) {
        Text('缩放')
          .fontSize(13)
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
          .fontSize(12)
          .fontColor(this.subTextColor())
          .width(36)
      }
      .width('100%')
      Row({ space: 10 }) {
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
          .fontColor('#FFFFFF')
          .backgroundColor(this.accentColor())
          .enabled(!this.processingCrop)
          .onClick(() => {
            this.confirmAvatarCrop();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.cardColor())
  }

  @Builder
  profileEditor() {
    Column({ space: 14 }) {
      Text('编辑个人资料')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Row({ space: 14 }) {
        if (this.profileAvatarPixelMap) {
          Image(this.profileAvatarPixelMap)
            .width(64)
            .height(64)
            .borderRadius(32)
            .objectFit(ImageFit.Cover)
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
        Column({ space: 8 }) {
          Button('选择头像')
            .height(34)
            .fontSize(13)
            .fontColor(this.accentColor())
            .backgroundColor(this.inputColor())
            .enabled(!this.savingProfile)
            .onClick(() => {
              this.pickProfileAvatar();
            })
          Button('使用默认头像')
            .height(30)
            .fontSize(12)
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
      TextInput({ text: this.profileNameInput, placeholder: '请输入昵称' })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(10)
        .maxLength(30)
        .enabled(!this.savingProfile)
        .onChange((value: string) => {
          this.profileNameInput = value;
        })
      Text('昵称和头像由你主动设置，将保存到账号服务端，不会申请华为账号敏感资料权限。')
        .fontSize(11)
        .lineHeight(17)
        .fontColor(this.subTextColor())
        .width('100%')
      Row({ space: 10 }) {
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
          .fontColor('#FFFFFF')
          .backgroundColor(this.accentColor())
          .enabled(!this.savingProfile)
          .onClick(() => {
            this.saveProfile();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.cardColor())
  }

  @Builder
  pointsCard() {
    Row() {
      Column({ space: 5 }) {
        Text('可用点数')
          .fontSize(13)
          .fontColor(this.subTextColor())
        Text(`${this.points}`)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accentColor())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Column({ space: 5 }) {
        Text('兑换比例')
          .fontSize(13)
          .fontColor(this.subTextColor())
        Text('1 元 = 10 点')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(this.cardColor())
  }

  @Builder
  rechargeSection() {
    Column({ space: 10 }) {
      Text('充值点数')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Grid() {
        ForEach(this.products, (product: RechargeProduct) => {
          GridItem() {
            Column({ space: 7 }) {
              Text(`${product.points} 点`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
              Text(product.localPrice || `预计 ¥${product.expectedPriceYuan}`)
                .fontSize(13)
                .fontColor(this.accentColor())
              if (this.purchasingProductId === product.productId) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.accentColor())
              }
            }
            .width('100%')
            .height(98)
            .justifyContent(FlexAlign.Center)
            .borderRadius(14)
            .backgroundColor(this.inputColor())
            .border({ width: 1, color: this.dividerColor() })
            .onClick(() => {
              this.buy(product);
            })
          }
        }, (product: RechargeProduct) => product.productId)
      }
      .columnsTemplate(this.rechargeColumnsTemplate())
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .height(this.rechargeGridHeight())
      .enableScrollInteraction(false)
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.cardColor())
  }

  @Builder
  accountActions() {
    Column() {
      Button('退出登录')
        .width('100%')
        .height(44)
        .fontColor('#E5484D')
        .backgroundColor(this.cardColor())
        .onClick(() => {
          this.logout();
        })
    }
    .width('100%')
  }

  @Builder
  loginGuide() {
    Column({ space: 8 }) {
      Text('登录后可用')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text('• 每个华为账号首次登录赠送 300 点\n• 点数余额和主题有效期可跨终端同步')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .lineHeight(22)
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.cardColor())
  }

  @Builder
  serviceHint() {
    if (!AccountCommerceConfig.isServerConfigured()) {
      Text('开发配置未完成：请在 AccountCommerceConfig.ets 填写 HTTPS 服务端地址，并在 module.json5 配置 AGC Client ID。')
        .fontSize(12)
        .fontColor('#C05A23')
        .lineHeight(18)
        .width('100%')
        .padding(14)
        .borderRadius(12)
        .backgroundColor(this.appDarkMode ? '#332216' : '#FFF3E8')
    } else {
      Text('登录和购买表示你同意应用的用户协议、隐私政策与点数服务规则。你主动设置的昵称和头像将保存到账号服务端并随华为账号同步；点数仅用于本应用数字内容，不支持转让或提现。')
        .fontSize(11)
        .fontColor(this.subTextColor())
        .lineHeight(17)
        .width('100%')
        .padding({ left: 4, right: 4 })
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
    return this.appDarkMode ? '#2CFFFFFF' : '#16000000';
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
    return rows * 98 + Math.max(0, rows - 1) * 10;
  }

  areaDimension(value: Length): number {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : 0;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
