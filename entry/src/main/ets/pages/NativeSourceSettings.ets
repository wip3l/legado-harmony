import { LengthMetrics, router } from '@kit.ArkUI';
import { BookSource, HttpClient, VerificationSupport, NativeSourceService, NativeVarItem, NativeVarOptions, NativeActionEntry,
  NativeLoginFieldSpec } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ExploreResultCache } from '../utils/ExploreResultCache';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

interface NativeSourceSettingsParams {
  bookSourceUrl?: string;
}

/** 原生书源的设置页：书源变量、账号登录和动作按钮。 */
@Entry
@Component
struct NativeSourceSettingsPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State sourceName: string = '';
  @State items: NativeVarItem[] = [];
  @State hasLogin: boolean = false;
  @State hasWebLogin: boolean = false;
  @State formFields: NativeLoginFieldSpec[] = [];
  @State hasSendCode: boolean = false;
  @State sendCodeLabel: string = '发送验证码';
  @State loggedIn: boolean = false;
  @State loginStatus: string = '';
  @State canCheckLogin: boolean = false;
  @State actions: NativeActionEntry[] = [];
  /** 动态选项加载失败的原因，按变量名。 */
  @State varNotes: Record<string, string> = {};
  @State runningAction: string = '';
  @State busy: boolean = false;
  @State dirty: boolean = false;
  private bookSourceUrl: string = '';
  private source: BookSource | null = null;
  private http: HttpClient = new HttpClient(10000);
  // 表单里填写的值只留在本页内存里，不落库。
  private formValues: Record<string, string> = {};

  aboutToAppear(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
    const params = router.getParams() as NativeSourceSettingsParams;
    this.bookSourceUrl = params && params.bookSourceUrl ? params.bookSourceUrl : '';
    this.loadSource();
  }

  onPageShow(): void {
    // 从登录页返回后刷新登录状态。
    if (this.source) this.refreshLoginState();
  }

  async loadSource(): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const source = await db.getBookSource(this.bookSourceUrl);
      if (!source || !NativeSourceService.isNative(source)) {
        HdsFeedback.showToast('未找到该原生书源');
        router.back();
        return;
      }
      this.source = source;
      this.sourceName = source.bookSourceName;
      this.items = NativeSourceService.varItems(source);
      const login = NativeSourceService.loginSpec(source);
      this.hasLogin = !!login;
      this.hasWebLogin = !!login && !!login.url;
      this.formFields = NativeSourceService.loginForm(source);
      this.hasSendCode = !!login && !!login.sendCode && this.formFields.length > 0;
      this.sendCodeLabel = login && login.sendCode && login.sendCode.label ? login.sendCode.label : '发送验证码';
      this.canCheckLogin = !!login && !!login.check;
      this.refreshLoginState();
      this.loadActions();
      this.loadVarOptions();
    } catch (e) {
      console.error('加载书源设置失败:', e);
      HdsFeedback.showToast('加载书源失败');
    }
  }

  /** 动作按钮可能依赖登录状态和变量，登录、保存之后都要重新取。 */
  async loadActions(): Promise<void> {
    if (!this.source) return;
    try {
      this.actions = await NativeSourceService.actions(this.source, this.http);
    } catch (e) {
      console.warn('加载书源动作失败:', (e as Error).message);
      this.actions = [];
    }
  }

  /** 变量的选项可以由书源脚本给出（例如测速后列出可用线路）；失败时保留写死的选项并显示原因。 */
  async loadVarOptions(): Promise<void> {
    if (!this.source) return;
    let loaded: Record<string, NativeVarOptions> = {};
    try {
      loaded = await NativeSourceService.varOptions(this.source, this.http);
    } catch (e) {
      console.warn('加载动态选项失败:', (e as Error).message);
      return;
    }
    const keys = Object.keys(loaded);
    if (keys.length === 0) return;
    const notes: Record<string, string> = {};
    this.items = this.items.map((item: NativeVarItem): NativeVarItem => {
      const result = loaded[item.key];
      if (!result) return item;
      if (result.error) {
        notes[item.key] = `选项获取失败：${result.error}`;
        return item;
      }
      const value = result.options.indexOf(item.value) >= 0 ? item.value : result.options[0];
      if (value !== item.value) this.dirty = true;
      return { key: item.key, label: item.label, options: result.options, value: value };
    });
    this.varNotes = notes;
  }

  refreshLoginState(): void {
    if (!this.source || !this.hasLogin) return;
    this.loggedIn = NativeSourceService.hasLoginCookies(this.source);
    const user = NativeSourceService.credential(this.source).user;
    this.loginStatus = this.loggedIn ? (user ? `已登录：${user}` : '已登录') : '未登录';
  }

  setValue(index: number, value: string): void {
    const next = this.items.slice();
    const item = next[index];
    next[index] = { key: item.key, label: item.label, options: item.options, value: value };
    this.items = next;
    this.dirty = true;
  }

  async save(): Promise<void> {
    if (!this.source) return;
    try {
      const variable = NativeSourceService.variableWithValues(this.source, this.items);
      const db = AppDatabase.getInstance();
      await db.updateBookSourceVariable(this.source.bookSourceUrl, variable);
      this.source.variable = variable;
      await ExploreResultCache.invalidateSources(getContext(this), [this.source.bookSourceUrl]);
      this.dirty = false;
      HdsFeedback.showToast('已保存');
      this.loadActions();
    } catch (e) {
      console.error('保存书源设置失败:', e);
      HdsFeedback.showToast('保存失败');
    }
  }

  openLogin(): void {
    if (!this.source) return;
    const login = NativeSourceService.loginSpec(this.source);
    if (!login || !login.url) return;
    const title = `${this.sourceName || '书源'} 登录`;
    // 网页登录可能换了账号，登录站点的 Cookie 不参与缓存分区，所以在这里清掉旧的缓存值。
    NativeSourceService.clearCache(this.source.bookSourceUrl);
    VerificationSupport.requestVerification(login.url, title, this.source);
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: login.url,
        title: title,
        requireLoginCookie: 'true',
        bookSourceBrowserAwaitToken: '',
        bookSourceBrowserPayloadToken: '',
        bookSourceVariable: this.source.variable || ''
      }
    });
  }

  /** 保存或清除表单登录换来的凭据。只存凭据，不存用户填的密码。 */
  async saveCredential(token: string, user: string): Promise<void> {
    if (!this.source) return;
    const loginInfo = NativeSourceService.loginInfoWith(this.source, token, user);
    await AppDatabase.getInstance().updateBookSourceLoginRuntime(this.source.bookSourceUrl,
      this.source.variable, this.source.loginHeader, loginInfo);
    this.source.loginInfo = loginInfo;
    await ExploreResultCache.invalidateSources(getContext(this), [this.source.bookSourceUrl]);
  }

  async submitForm(): Promise<void> {
    if (!this.source || this.busy) return;
    this.busy = true;
    this.loginStatus = '正在登录…';
    try {
      const result = await NativeSourceService.submitLogin(this.source, this.http, this.formValues);
      if (result.ok) {
        // 没有单独声明凭据的接口（靠 Cookie 维持登录）也记一个标记，用来显示已登录。
        await this.saveCredential(result.token || 'ok', result.user);
        HdsFeedback.showToast(result.message || '登录成功');
      } else {
        HdsFeedback.showToast(result.message || '登录失败');
      }
    } catch (e) {
      HdsFeedback.showToast(`登录失败：${(e as Error).message || '未知错误'}`);
    } finally {
      this.busy = false;
      this.refreshLoginState();
      this.loadActions();
    }
  }

  async sendCode(): Promise<void> {
    if (!this.source || this.busy) return;
    this.busy = true;
    try {
      HdsFeedback.showToast(await NativeSourceService.sendLoginCode(this.source, this.http, this.formValues));
    } catch (e) {
      HdsFeedback.showToast(`操作失败：${(e as Error).message || '未知错误'}`);
    } finally {
      this.busy = false;
    }
  }

  async checkLogin(): Promise<void> {
    if (!this.source || this.busy) return;
    this.busy = true;
    this.loginStatus = '正在检查…';
    try {
      const state = await NativeSourceService.checkLogin(this.source, this.http);
      this.loggedIn = state.ok;
      this.loginStatus = state.ok ? (state.name ? `已登录：${state.name}` : '已登录') : (state.message || '未登录');
    } catch (e) {
      this.loginStatus = `检查失败：${(e as Error).message || '未知错误'}`;
    } finally {
      this.busy = false;
    }
  }

  async logout(): Promise<void> {
    if (!this.source) return;
    NativeSourceService.logout(this.source);
    try {
      await this.saveCredential('', '');
    } catch (e) {
      console.warn('清除登录凭据失败:', e);
    }
    this.refreshLoginState();
    this.loadActions();
    HdsFeedback.showToast('已退出登录');
  }

  async runAction(action: NativeActionEntry): Promise<void> {
    if (!this.source || this.busy) return;
    if (action.open) {
      VerificationSupport.requestVerification(action.open, action.label, this.source);
      router.pushUrl({
        url: 'pages/VerifyWeb',
        params: { url: action.open, title: action.label, requireLoginCookie: 'false', readerCommentMode: 'false' }
      });
      return;
    }
    this.busy = true;
    this.runningAction = action.label;
    try {
      HdsFeedback.showToast(await NativeSourceService.runAction(this.source, this.http, action.index));
      // 脚本按钮可能改了书源变量或登录状态，重新读一遍。
      if (!this.dirty) this.items = NativeSourceService.varItems(this.source);
      this.refreshLoginState();
      this.loadActions();
    } catch (e) {
      HdsFeedback.showToast(`操作失败：${(e as Error).message || '未知错误'}`);
    } finally {
      this.busy = false;
      this.runningAction = '';
    }
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.MD })
  }

  @Builder
  actionButton(label: string, color: string, action: () => void) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(color)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
      .borderRadius(ThemeRuntime.smallRadius())
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      .opacity(this.busy ? 0.5 : 1)
      .onClick(() => action())
  }

  build() {
    Column() {
      Row() {
        ImmersiveBackButton({ iconColor: ThemeRuntime.primaryTextColor(this.appDarkMode), darkMode: this.appDarkMode,
          buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
          onBack: () => router.back() })

        Text('书源设置')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .layoutWeight(1)

        if (this.items.length > 0) {
          Text('保存')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.dirty ? ThemeRuntime.accentColor(this.appDarkMode) :
              ThemeRuntime.subTextColor(this.appDarkMode))
            .width(60)
            .height(56)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.save();
            })
        }
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ top: this.statusBarHeight })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          Text(this.sourceName)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .width('100%')
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL })

          if (this.items.length > 0) {
            this.sectionTitle('变量')
            ForEach(this.items, (item: NativeVarItem, index: number) => {
              Row() {
                Text(item.label)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
                  .width(96)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                if (item.options.length > 0) {
                  Select(item.options.map((option: string): SelectOption => ({ value: option })))
                    .selected(Math.max(0, item.options.indexOf(item.value)))
                    .value(item.value)
                    .font({ size: AppFontSize.BODY })
                    .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
                    .divider(null)
                    .optionBgColor(Color.Transparent)
                    .optionFontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
                    .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
                    .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
                    .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
                    .menuBackgroundBlurStyle(BlurStyle.NONE)
                    .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
                    .layoutWeight(1)
                    .onSelect((_selected: number, text: string) => {
                      this.setValue(index, text);
                    })
                } else {
                  TextInput({ text: item.value, placeholder: '未填写' })
                    .fontSize(AppFontSize.BODY)
                    .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
                    .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
                    .borderRadius(ThemeRuntime.smallRadius())
                    .layoutWeight(1)
                    .onChange((value: string) => {
                      if (value !== this.items[index].value) this.setValue(index, value);
                    })
                }
              }
              .width('100%')
              .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
              .alignItems(VerticalAlign.Center)

              if (this.varNotes[item.key]) {
                Text(this.varNotes[item.key])
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
                  .width('100%')
                  .padding({ left: AppSpacing.XL + 96, right: AppSpacing.XL })
              }
            }, (item: NativeVarItem) => `${item.key}_${item.options.join('|')}_${item.options.length > 0 ? item.value : ''}`)
          }

          if (this.hasLogin) {
            this.sectionTitle('账号')
            Text(this.loginStatus)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.loggedIn ? ThemeRuntime.successColor(this.appDarkMode) :
                ThemeRuntime.subTextColor(this.appDarkMode))
              .width('100%')
              .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })

            ForEach(this.formFields, (field: NativeLoginFieldSpec) => {
              Row() {
                Text(field.label || field.key)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
                  .width(96)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                TextInput({ placeholder: '请输入' })
                  .type(field.secret === true ? InputType.Password : InputType.Normal)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
                  .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
                  .borderRadius(ThemeRuntime.smallRadius())
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.formValues[field.key] = value;
                  })
              }
              .width('100%')
              .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
              .alignItems(VerticalAlign.Center)
            }, (field: NativeLoginFieldSpec) => field.key)

            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(AppSpacing.MD),
              cross: LengthMetrics.vp(AppSpacing.MD) } }) {
              if (this.formFields.length > 0) {
                this.actionButton('登录', ThemeRuntime.accentColor(this.appDarkMode), () => {
                  this.submitForm();
                })
                if (this.hasSendCode) {
                  this.actionButton(this.sendCodeLabel, ThemeRuntime.primaryTextColor(this.appDarkMode), () => {
                    this.sendCode();
                  })
                }
              }
              if (this.hasWebLogin) {
                this.actionButton(this.formFields.length > 0 ? '网页登录' : (this.loggedIn ? '重新登录' : '登录'),
                  ThemeRuntime.accentColor(this.appDarkMode), () => this.openLogin())
              }
              if (this.canCheckLogin) {
                this.actionButton('检查登录', ThemeRuntime.primaryTextColor(this.appDarkMode), () => {
                  this.checkLogin();
                })
              }
              if (this.loggedIn) {
                this.actionButton('退出登录', ThemeRuntime.dangerColor(this.appDarkMode), () => {
                  this.logout();
                })
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM })
          }

          if (this.actions.length > 0) {
            this.sectionTitle('操作')
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(AppSpacing.MD),
              cross: LengthMetrics.vp(AppSpacing.MD) } }) {
              ForEach(this.actions, (action: NativeActionEntry) => {
                this.actionButton(action.label, ThemeRuntime.primaryTextColor(this.appDarkMode), () => {
                  this.runAction(action);
                })
              }, (action: NativeActionEntry) => `${action.index}_${action.label}`)
            }
            .width('100%')
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL })

            if (this.runningAction) {
              Text(`正在执行：${this.runningAction}`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
                .width('100%')
                .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM })
            }
          }

          if (this.items.length === 0 && !this.hasLogin && this.actions.length === 0) {
            Text('该书源没有可设置的项目')
              .fontSize(AppFontSize.BODY)
              .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 80 })
          }
        }
        .width('100%')
        .padding({ bottom: this.navBarHeight + AppSpacing.XL })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }
}
