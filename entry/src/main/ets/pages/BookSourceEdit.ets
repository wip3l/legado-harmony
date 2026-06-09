import { router } from '@kit.ArkUI';
import { BookSource } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { promptAction } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { HttpClient } from '../core/http/HttpClient';

@Entry
@Component
struct BookSourceEditPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State bookSourceUrl: string = '';
  @State source: BookSource = new BookSource();
  @State isLoading: boolean = false;
  @State currentTab: number = 0;
  @State sourceLoadedVersion: number = 0;
  @State shushanEmail: string = '';
  @State shushanPassword: string = '';
  @State shushanLoggingIn: boolean = false;

  aboutToAppear() {
    this.syncBars();
    const params = router.getParams() as Record<string, string>;
    if (params && params['bookSourceUrl']) {
      this.bookSourceUrl = params['bookSourceUrl'];
      if (this.bookSourceUrl) {
        this.loadSource();
      }
    }
  }

  onPageShow(): void {
    this.syncBars();
  }

  async loadSource() {
    this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const source = await db.getBookSource(this.bookSourceUrl);
      if (source) {
        this.source = source;
        this.restoreShushanLoginFields();
        this.currentTab = 0;
        this.sourceLoadedVersion++;
      }
    } catch (e) {
      console.error('加载书源失败:', e);
    } finally {
      this.isLoading = false;
    }
  }

  async saveSource() {
    if (!this.source.bookSourceUrl) {
      promptAction.showToast({ message: '请输入书源地址' });
      return;
    }
    if (!this.source.bookSourceName) {
      promptAction.showToast({ message: '请输入书源名称' });
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      const existing = await db.getBookSource(this.source.bookSourceUrl);
      if (existing) {
        await db.updateBookSource(this.source);
      } else {
        await db.insertBookSource(this.source);
      }
      this.clearShushanPendingVerificationIfReady();
      promptAction.showToast({ message: '保存成功' });
      router.back();
    } catch (e) {
      console.error('保存书源失败:', e);
      promptAction.showToast({ message: '保存失败' });
    }
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(24)
          .fontColor(this.primaryTextColor())
          .width(40)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back();
          })

        Text(this.bookSourceUrl ? '编辑书源' : '新建书源')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)

        Text('保存')
          .fontSize(16)
          .fontColor('#007DFF')
          .width(60)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.saveSource();
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(this.cardColor())
      .alignItems(VerticalAlign.Center)

      // Tab栏
      Row() {
        Text('基本')
          .fontSize(14)
          .fontColor(this.currentTab === 0 ? '#007DFF' : this.secondaryTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .borderWidth({ bottom: this.currentTab === 0 ? 2 : 0 })
          .borderColor('#007DFF')
          .onClick(() => {
            this.currentTab = 0;
          })

        Text('搜索')
          .fontSize(14)
          .fontColor(this.currentTab === 1 ? '#007DFF' : this.secondaryTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .borderWidth({ bottom: this.currentTab === 1 ? 2 : 0 })
          .borderColor('#007DFF')
          .onClick(() => {
            this.currentTab = 1;
          })

        Text('发现')
          .fontSize(14)
          .fontColor(this.currentTab === 2 ? '#007DFF' : this.secondaryTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .borderWidth({ bottom: this.currentTab === 2 ? 2 : 0 })
          .borderColor('#007DFF')
          .onClick(() => {
            this.currentTab = 2;
          })

        Text('详情')
          .fontSize(14)
          .fontColor(this.currentTab === 3 ? '#007DFF' : this.secondaryTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .borderWidth({ bottom: this.currentTab === 3 ? 2 : 0 })
          .borderColor('#007DFF')
          .onClick(() => {
            this.currentTab = 3;
          })

        Text('目录')
          .fontSize(14)
          .fontColor(this.currentTab === 4 ? '#007DFF' : this.secondaryTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .borderWidth({ bottom: this.currentTab === 4 ? 2 : 0 })
          .borderColor('#007DFF')
          .onClick(() => {
            this.currentTab = 4;
          })

        Text('正文')
          .fontSize(14)
          .fontColor(this.currentTab === 5 ? '#007DFF' : this.secondaryTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .borderWidth({ bottom: this.currentTab === 5 ? 2 : 0 })
          .borderColor('#007DFF')
          .onClick(() => {
            this.currentTab = 5;
          })
      }
      .width('100%')
      .backgroundColor(this.cardColor())
      .borderWidth({ bottom: 1 })
      .borderColor(this.dividerColor())

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
          Text('加载书源中...')
            .fontSize(14)
            .fontColor(this.secondaryTextColor())
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 内容区域
        Scroll() {
          Column() {
            if (this.currentTab === 0) {
              this.basicTabBuilder()
            } else if (this.currentTab === 1) {
              this.searchTabBuilder()
            } else if (this.currentTab === 2) {
              this.exploreTabBuilder()
            } else if (this.currentTab === 3) {
              this.infoTabBuilder()
            } else if (this.currentTab === 4) {
              this.tocTabBuilder()
            } else if (this.currentTab === 5) {
              this.contentTabBuilder()
            }
          }
          .width('100%')
          .padding(16)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  basicTabBuilder() {
    Column({ space: 12 }) {
      Text(`${this.sourceLoadedVersion}`)
        .fontSize(0.1)
        .height(0)
        .opacity(0)

      this.inputItemBuilder('书源名称', this.source.bookSourceName, (value: string) => {
        this.source.bookSourceName = value;
      })

      this.inputItemBuilder('书源地址', this.source.bookSourceUrl, (value: string) => {
        this.source.bookSourceUrl = value;
      })

      this.inputItemBuilder('书源分组', this.source.bookSourceGroup, (value: string) => {
        this.source.bookSourceGroup = value;
      })

      this.inputItemBuilder('书源备注', this.source.bookSourceComment, (value: string) => {
        this.source.bookSourceComment = value;
      })

      this.inputItemBuilder('登录地址', this.source.loginUrl, (value: string) => {
        this.source.loginUrl = value;
      })

      this.inputItemBuilder('登录检测JS', this.source.loginCheckJs, (value: string) => {
        this.source.loginCheckJs = value;
      })

      this.inputItemBuilder('登录密钥', this.source.loginHeader, (value: string) => {
        this.source.loginHeader = value;
      })

      if (this.isShushanSource()) {
        this.shushanLoginBuilder()
      }

      this.inputItemBuilder('URL正则', this.source.bookUrlPattern, (value: string) => {
        this.source.bookUrlPattern = value;
      })

      this.inputItemBuilder('搜索地址', this.source.searchUrl, (value: string) => {
        this.source.searchUrl = value;
      })

      this.inputItemBuilder('发现地址', this.source.exploreUrl, (value: string) => {
        this.source.exploreUrl = value;
      })

      this.inputItemBuilder('JS库', this.source.jsLib, (value: string) => {
        this.source.jsLib = value;
      })

      this.inputItemBuilder('请求头', this.source.header, (value: string) => {
        this.source.header = value;
      })

      Row() {
        Text('启用书源')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.source.enabled })
          .onChange((isOn: boolean) => {
            this.source.enabled = isOn;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Row() {
        Text('启用发现')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.source.enabledExplore })
          .onChange((isOn: boolean) => {
            this.source.enabledExplore = isOn;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      this.inputItemBuilder('权重', String(this.source.weight), (value: string) => {
        this.source.weight = parseInt(value) || 0;
      })
    }
  }

  @Builder
  shushanLoginBuilder() {
    Column({ space: 10 }) {
      Text('书山账号登录')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .width('100%')

      TextInput({ text: this.shushanEmail, placeholder: '邮箱' })
        .width('100%')
        .height(44)
        .borderRadius(8)
        .backgroundColor(this.cardColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.placeholderTextColor())
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          this.shushanEmail = value;
          this.saveShushanLoginFieldsToSession();
        })

      TextInput({ text: this.shushanPassword, placeholder: '密码' })
        .type(InputType.Password)
        .width('100%')
        .height(44)
        .borderRadius(8)
        .backgroundColor(this.cardColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.placeholderTextColor())
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          this.shushanPassword = value;
          this.saveShushanLoginFieldsToSession();
        })

      Button(this.shushanLoggingIn ? '登录中...' : '登录并保存密钥')
        .width('100%')
        .height(40)
        .borderRadius(8)
        .backgroundColor('#007DFF')
        .fontColor('#FFFFFF')
        .enabled(!this.shushanLoggingIn)
        .onClick(() => {
          this.loginShushan();
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  searchTabBuilder() {
    Column({ space: 12 }) {
      Text('搜索规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('书籍列表', this.source.searchRule.bookList, (value: string) => {
        this.source.searchRule.bookList = value;
      })

      this.inputItemBuilder('书名', this.source.searchRule.name, (value: string) => {
        this.source.searchRule.name = value;
      })

      this.inputItemBuilder('作者', this.source.searchRule.author, (value: string) => {
        this.source.searchRule.author = value;
      })

      this.inputItemBuilder('封面', this.source.searchRule.coverUrl, (value: string) => {
        this.source.searchRule.coverUrl = value;
      })

      this.inputItemBuilder('简介', this.source.searchRule.intro, (value: string) => {
        this.source.searchRule.intro = value;
      })

      this.inputItemBuilder('分类', this.source.searchRule.kind, (value: string) => {
        this.source.searchRule.kind = value;
      })

      this.inputItemBuilder('最新章节', this.source.searchRule.lastChapter, (value: string) => {
        this.source.searchRule.lastChapter = value;
      })

      this.inputItemBuilder('详情页', this.source.searchRule.bookUrl, (value: string) => {
        this.source.searchRule.bookUrl = value;
      })

      this.inputItemBuilder('字数', this.source.searchRule.wordCount, (value: string) => {
        this.source.searchRule.wordCount = value;
      })
    }
  }

  @Builder
  exploreTabBuilder() {
    Column({ space: 12 }) {
      Text('发现规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('书籍列表', this.source.exploreRule.bookList, (value: string) => {
        this.source.exploreRule.bookList = value;
      })

      this.inputItemBuilder('书名', this.source.exploreRule.name, (value: string) => {
        this.source.exploreRule.name = value;
      })

      this.inputItemBuilder('作者', this.source.exploreRule.author, (value: string) => {
        this.source.exploreRule.author = value;
      })

      this.inputItemBuilder('封面', this.source.exploreRule.coverUrl, (value: string) => {
        this.source.exploreRule.coverUrl = value;
      })

      this.inputItemBuilder('简介', this.source.exploreRule.intro, (value: string) => {
        this.source.exploreRule.intro = value;
      })

      this.inputItemBuilder('分类', this.source.exploreRule.kind, (value: string) => {
        this.source.exploreRule.kind = value;
      })

      this.inputItemBuilder('最新章节', this.source.exploreRule.lastChapter, (value: string) => {
        this.source.exploreRule.lastChapter = value;
      })

      this.inputItemBuilder('详情页', this.source.exploreRule.bookUrl, (value: string) => {
        this.source.exploreRule.bookUrl = value;
      })

      this.inputItemBuilder('字数', this.source.exploreRule.wordCount, (value: string) => {
        this.source.exploreRule.wordCount = value;
      })
    }
  }

  @Builder
  infoTabBuilder() {
    Column({ space: 12 }) {
      Text('详情规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('初始化', this.source.bookInfoRule.init, (value: string) => {
        this.source.bookInfoRule.init = value;
      })

      this.inputItemBuilder('书名', this.source.bookInfoRule.name, (value: string) => {
        this.source.bookInfoRule.name = value;
      })

      this.inputItemBuilder('作者', this.source.bookInfoRule.author, (value: string) => {
        this.source.bookInfoRule.author = value;
      })

      this.inputItemBuilder('封面', this.source.bookInfoRule.coverUrl, (value: string) => {
        this.source.bookInfoRule.coverUrl = value;
      })

      this.inputItemBuilder('简介', this.source.bookInfoRule.intro, (value: string) => {
        this.source.bookInfoRule.intro = value;
      })

      this.inputItemBuilder('分类', this.source.bookInfoRule.kind, (value: string) => {
        this.source.bookInfoRule.kind = value;
      })

      this.inputItemBuilder('最新章节', this.source.bookInfoRule.lastChapter, (value: string) => {
        this.source.bookInfoRule.lastChapter = value;
      })

      this.inputItemBuilder('字数', this.source.bookInfoRule.wordCount, (value: string) => {
        this.source.bookInfoRule.wordCount = value;
      })

      this.inputItemBuilder('更新时间', this.source.bookInfoRule.updateTime, (value: string) => {
        this.source.bookInfoRule.updateTime = value;
      })

      this.inputItemBuilder('目录地址', this.source.bookInfoRule.tocUrl, (value: string) => {
        this.source.bookInfoRule.tocUrl = value;
      })
    }
  }

  @Builder
  tocTabBuilder() {
    Column({ space: 12 }) {
      Text('目录规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('章节列表', this.source.tocRule.chapterList, (value: string) => {
        this.source.tocRule.chapterList = value;
      })

      this.inputItemBuilder('章节名称', this.source.tocRule.chapterName, (value: string) => {
        this.source.tocRule.chapterName = value;
      })

      this.inputItemBuilder('章节地址', this.source.tocRule.chapterUrl, (value: string) => {
        this.source.tocRule.chapterUrl = value;
      })

      this.inputItemBuilder('VIP标记', this.source.tocRule.isVip, (value: string) => {
        this.source.tocRule.isVip = value;
      })

      this.inputItemBuilder('付费标记', this.source.tocRule.isPay, (value: string) => {
        this.source.tocRule.isPay = value;
      })

      this.inputItemBuilder('更新时间', this.source.tocRule.updateTime, (value: string) => {
        this.source.tocRule.updateTime = value;
      })
    }
  }

  @Builder
  contentTabBuilder() {
    Column({ space: 12 }) {
      Text('正文规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('正文内容', this.source.contentRule.content, (value: string) => {
        this.source.contentRule.content = value;
      })

      this.inputItemBuilder('章节标题', this.source.contentRule.title, (value: string) => {
        this.source.contentRule.title = value;
      })

      this.inputItemBuilder('图片', this.source.contentRule.images, (value: string) => {
        this.source.contentRule.images = value;
      })

      this.inputItemBuilder('替换净化', this.source.contentRule.replaceRegex, (value: string) => {
        this.source.contentRule.replaceRegex = value;
      })

      this.inputItemBuilder('图片样式', this.source.contentRule.imageStyle, (value: string) => {
        this.source.contentRule.imageStyle = value;
      })
    }
  }

  async loginShushan(): Promise<void> {
    const email = this.shushanEmail.trim();
    const password = this.shushanPassword.trim();
    if (!email || !password) {
      promptAction.showToast({ message: '请输入书山账号邮箱和密码' });
      return;
    }
    this.saveShushanLoginFieldsToSession();
    this.shushanLoggingIn = true;
    try {
      const http = new HttpClient(10000);
      let lastMessage = '书山登录失败';
      for (const host of this.shushanHostCandidates()) {
        const resp = await http.execute({
          url: `${host}/login`,
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.7151.104 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'X-Novel-Token': 'SHUSAN_READ_2025'
          },
          body: `email=${encodeURIComponent(email)}&password=${encodeURIComponent(password)}`
        });
        if (!resp.success || !resp.body) {
          continue;
        }
        const root = JSON.parse(resp.body) as Record<string, Object>;
        if (String(root['code'] || '') !== '200') {
          lastMessage = String(root['message'] || lastMessage);
          continue;
        }
        const data = (root['data'] || {}) as Record<string, Object>;
        const user = (data['user'] || {}) as Record<string, Object>;
        const apiKey = String(user['api_key'] || '').trim();
        if (!apiKey) {
          lastMessage = '登录成功但未返回密钥';
          continue;
        }
        this.source.loginHeader = apiKey;
        await this.saveSourceWithoutBack();
        this.clearShushanPendingVerificationIfReady();
        promptAction.showToast({ message: '书山登录成功，密钥已保存' });
        this.sourceLoadedVersion++;
        return;
      }
      promptAction.showToast({ message: lastMessage });
    } catch (e) {
      console.error('书山登录失败:', e);
      promptAction.showToast({ message: '书山登录失败' });
    } finally {
      this.shushanLoggingIn = false;
    }
  }

  async saveSourceWithoutBack(): Promise<void> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    const existing = await db.getBookSource(this.source.bookSourceUrl);
    if (existing) {
      await db.updateBookSource(this.source);
    } else {
      await db.insertBookSource(this.source);
    }
  }

  clearShushanPendingVerificationIfReady(): void {
    if (!this.isShushanSource() || !(this.source.loginHeader || '').trim()) return;
    AppStorage.setOrCreate('pendingVerificationUrl', '');
    AppStorage.setOrCreate('pendingVerificationTitle', '');
    AppStorage.setOrCreate('verificationCompletedAt', Date.now());
  }

  restoreShushanLoginFields(): void {
    if (!this.isShushanSource()) return;
    const key = this.shushanSessionKey();
    this.shushanEmail = AppStorage.get<string>(`${key}:email`) || this.shushanEmail;
    this.shushanPassword = AppStorage.get<string>(`${key}:password`) || this.shushanPassword;
  }

  saveShushanLoginFieldsToSession(): void {
    if (!this.isShushanSource()) return;
    const key = this.shushanSessionKey();
    AppStorage.setOrCreate(`${key}:email`, this.shushanEmail);
    AppStorage.setOrCreate(`${key}:password`, this.shushanPassword);
  }

  shushanSessionKey(): string {
    return `shushanLogin:${encodeURIComponent(this.source.bookSourceUrl || this.bookSourceUrl || '')}`;
  }

  isShushanSource(): boolean {
    const raw = `${this.source.bookSourceUrl || ''}\n${this.source.searchUrl || ''}\n${this.source.exploreUrl || ''}\n` +
      `${this.source.loginUrl || ''}\n${this.source.jsLib || ''}\n${this.source.header || ''}`;
    return raw.includes('vossc.com') || raw.includes('SHUSAN_READ_2025');
  }

  shushanHost(): string {
    const raw = `${this.source.bookSourceUrl || ''}\n${this.source.loginUrl || ''}\n${this.source.jsLib || ''}`;
    const match = raw.match(/https?:\/\/[^'"`\s,)]+vossc\.com/i);
    return match ? match[0] : 'https://v1.vossc.com';
  }

  shushanHostCandidates(): string[] {
    const hosts = [
      this.shushanHost(),
      'http://1.94.248.5:7001',
      'https://v1.vossc.com',
      'https://v2.vossc.com',
      'https://v3.vossc.com',
      'https://v4.vossc.com'
    ];
    const result: string[] = [];
    for (const host of hosts) {
      if (host && !result.includes(host)) result.push(host);
    }
    return result;
  }

  @Builder
  inputItemBuilder(label: string, value: string, onChange: (value: string) => void) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .margin({ bottom: 4 })

      TextInput({ text: value, placeholder: `请输入${label}` })
        .width('100%')
        .height(44)
        .borderRadius(8)
        .backgroundColor(this.cardColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.placeholderTextColor())
        .padding({ left: 12, right: 12 })
        .onChange((val: string) => {
          onChange(val);
        })
    }
    .width('100%')
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  secondaryTextColor(): string {
    return this.appDarkMode ? '#B8BDC7' : '#666666';
  }

  dividerColor(): string {
    return this.appDarkMode ? '#2A2D33' : '#E0E0E0';
  }

  placeholderTextColor(): string {
    return this.appDarkMode ? '#6F7480' : '#999999';
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
