import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import zlib from '@ohos.zlib';
import { syncSystemBars } from '../utils/SystemBars';
import { CoverAlbum, CoverGallerySettings } from '../utils/CoverGallerySettings';
import { CoverGalleryStore, CoverGallerySnapshot } from '../utils/CoverGalleryStore';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';

class CoverGalleryExportResult {
  zipPath: string = '';
  imageCount: number = 0;
}

@Entry
@Component
struct CoverGalleryManagerPage {
  @StorageLink('bookshelfCoverAlbums') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State albums: CoverAlbum[] = [];
  @State selectedAlbumId: string = '';
  @State newAlbumName: string = '';
  @State renameAlbumName: string = '';
  @State showCreateAlbumDialog: boolean = false;
  @State showDeleteAlbumConfirm: boolean = false;
  @State showImageManager: boolean = false;
  @State selectedImages: string[] = [];
  @State albumCount: number = 0;
  @State totalCoverSize: number = 0;
  @State selectedAlbumCoverSize: number = 0;

  aboutToAppear(): void {
    this.reloadAlbums();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadAlbums();
    this.syncBars();
  }

  build() {
    Stack() {
      Column() {
        this.titleBar()

        Scroll() {
          Column() {
            this.summaryPanel()

            this.albumSectionTitle()
            this.albumListPanel()

            if (this.getSelectedAlbum()) {
              this.sectionTitle('编辑')
              this.selectedAlbumPanel()
            }
          }
          .width('100%')
          .padding({ bottom: 32 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
      .backgroundColor(this.pageColor())

      if (this.showDeleteAlbumConfirm) {
        this.deleteAlbumConfirmDialog()
      }

      if (this.showCreateAlbumDialog) {
        this.createAlbumDialog()
      }

      if (this.showImageManager) {
        this.imageManagerDialog()
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  async reloadAlbums(): Promise<void> {
    try {
      const snapshot = await CoverGalleryStore.load(getContext(this));
      const localAlbumsRaw = this.bookshelfCoverAlbums;
      const albumsRaw = this.hasAlbumPayload(snapshot.albumsRaw) || !this.hasAlbumPayload(localAlbumsRaw) ?
        snapshot.albumsRaw : localAlbumsRaw;
      this.bookshelfCoverAlbums = albumsRaw;
      this.loadAlbums(albumsRaw);
      if (!this.hasAlbumPayload(snapshot.albumsRaw) && this.hasAlbumPayload(albumsRaw)) {
        this.persistCoverSettings(albumsRaw);
      }
    } catch (e) {
      console.warn('重新加载封面图集失败:', e);
      this.loadAlbums(this.bookshelfCoverAlbums);
    }
  }

  loadAlbums(raw: string, preferredAlbumId?: string): void {
    const albums = CoverGallerySettings.parseAlbums(raw);
    this.albums = albums;
    if (preferredAlbumId && CoverGallerySettings.getAlbum(albums, preferredAlbumId)) {
      this.selectedAlbumId = preferredAlbumId;
    }
    if (this.selectedAlbumId && !CoverGallerySettings.getAlbum(albums, this.selectedAlbumId)) {
      this.selectedAlbumId = '';
      this.renameAlbumName = '';
    }
    if (!this.selectedAlbumId && albums.length > 0) {
      this.selectedAlbumId = albums[0].id;
      this.renameAlbumName = albums[0].name;
      this.selectedImages = [];
    }
    const selectedAlbum = CoverGallerySettings.getAlbum(albums, this.selectedAlbumId);
    if (selectedAlbum) {
      this.renameAlbumName = selectedAlbum.name;
    }
    this.refreshAlbumStats(albums, this.selectedAlbumId);
  }

  saveAlbums(albums: CoverAlbum[], preferredAlbumId?: string): void {
    const selectedId = preferredAlbumId ?? this.selectedAlbumId;
    const albumsRaw = CoverGallerySettings.encodeAlbums(albums);
    this.bookshelfCoverAlbums = albumsRaw;
    this.loadAlbums(albumsRaw, selectedId);
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    AppStorage.setOrCreate('coverGalleryUpdateTime', Date.now());
    this.persistCoverSettings(albumsRaw);
  }

  async persistCoverSettings(albumsRaw?: string): Promise<void> {
    const context = getContext(this);
    let snapshot = new CoverGallerySnapshot();
    try {
      snapshot = await CoverGalleryStore.load(context);
    } catch (e) {
      console.warn('加载现有封面图集配置失败:', e);
    }
    snapshot.albumsRaw = albumsRaw ?? this.bookshelfCoverAlbums;
    snapshot.lightAlbumId = this.bookshelfLightCoverAlbumId;
    snapshot.darkAlbumId = this.bookshelfDarkCoverAlbumId;
    CoverGalleryStore.applyToStorage(snapshot);
    CoverGalleryStore.save(context, snapshot).then(() => {
      RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext);
    }).catch((e: Error) => {
      console.warn('保存封面图集配置失败:', e);
    });
  }

  selectAlbum(album: CoverAlbum): void {
    this.selectedAlbumId = album.id;
    this.renameAlbumName = album.name;
    this.selectedImages = [];
    this.refreshAlbumStats(this.albums, this.selectedAlbumId);
  }

  getSelectedAlbum(): CoverAlbum | null {
    return CoverGallerySettings.getAlbum(this.albums, this.selectedAlbumId);
  }

  createAlbum(): void {
    const name = this.newAlbumName.trim();
    if (!name) {
      promptAction.showToast({ message: '图集名称不能为空' });
      return;
    }
    const album = CoverGallerySettings.createAlbum(name);
    const next = [...this.albums, album];
    this.saveAlbums(next, album.id);
    this.newAlbumName = '';
    this.showCreateAlbumDialog = false;
    this.hideKeyboard();
    promptAction.showToast({ message: '已新建图集' });
  }

  renameSelectedAlbum(): void {
    const name = this.renameAlbumName.trim();
    if (!name) {
      promptAction.showToast({ message: '请输入图集名称' });
      return;
    }
    const next = this.albums.map((album: CoverAlbum) => {
      if (album.id === this.selectedAlbumId) {
        const item = new CoverAlbum();
        item.id = album.id;
        item.name = name;
        item.covers = [...album.covers];
        return item;
      }
      return album;
    });
    this.saveAlbums(next, this.selectedAlbumId);
    this.hideKeyboard();
    promptAction.showToast({ message: '已重命名图集' });
  }

  requestDeleteSelectedAlbum(): void {
    if (!this.selectedAlbumId) {
      return;
    }
    this.showDeleteAlbumConfirm = true;
  }

  deleteSelectedAlbum(): void {
    if (!this.selectedAlbumId) {
      return;
    }
    const next = this.albums.filter((album: CoverAlbum) => album.id !== this.selectedAlbumId);
    if (this.bookshelfLightCoverAlbumId === this.selectedAlbumId) {
      this.bookshelfLightCoverAlbumId = '';
    }
    if (this.bookshelfDarkCoverAlbumId === this.selectedAlbumId) {
      this.bookshelfDarkCoverAlbumId = '';
    }
    this.saveAlbums(next, next.length > 0 ? next[0].id : '');
    this.selectedAlbumId = '';
    this.renameAlbumName = '';
    this.selectedImages = [];
    this.showDeleteAlbumConfirm = false;
    if (next.length > 0) {
      this.selectAlbum(next[0]);
    } else {
      this.refreshAlbumStats(this.albums, this.selectedAlbumId);
    }
    promptAction.showToast({ message: '已删除图集' });
  }

  openImageManager(): void {
    if (!this.getSelectedAlbum()) {
      return;
    }
    this.selectedImages = [];
    this.showImageManager = true;
  }

  closeImageManager(): void {
    this.showImageManager = false;
    this.selectedImages = [];
  }

  isImageSelected(cover: string): boolean {
    return this.selectedImages.includes(cover);
  }

  toggleImageSelection(cover: string): void {
    if (this.isImageSelected(cover)) {
      this.selectedImages = this.selectedImages.filter((item: string) => item !== cover);
    } else {
      this.selectedImages = [...this.selectedImages, cover];
    }
  }

  selectAllImages(): void {
    const album = this.getSelectedAlbum();
    this.selectedImages = album ? [...album.covers] : [];
  }

  clearImageSelection(): void {
    this.selectedImages = [];
  }

  deleteSelectedImages(): void {
    const album = this.getSelectedAlbum();
    if (!album) {
      return;
    }
    if (this.selectedImages.length === 0) {
      promptAction.showToast({ message: '请先选择图片' });
      return;
    }
    const deleteSet = new Set<string>(this.selectedImages);
    const next = this.albums.map((item: CoverAlbum) => {
      if (item.id === album.id) {
        const updated = new CoverAlbum();
        updated.id = item.id;
        updated.name = item.name;
        updated.covers = item.covers.filter((cover: string) => !deleteSet.has(cover));
        return updated;
      }
      return item;
    });
    const count = this.selectedImages.length;
    this.saveAlbums(next, album.id);
    this.selectedImages = [];
    promptAction.showToast({ message: `已删除 ${count} 张图片` });
  }

  async pickAlbumImages(): Promise<void> {
    const album = this.getSelectedAlbum();
    if (!album) {
      promptAction.showToast({ message: '请先选择或新建图集' });
      return;
    }
    try {
      const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 50;
      const result = await new picker.PhotoViewPicker(getContext(this)).select(options);
      if (!result || result.photoUris.length === 0) {
        return;
      }
      await this.addCoversToAlbum(album.id, result.photoUris);
      promptAction.showToast({ message: `已导入 ${result.photoUris.length} 张图片` });
    } catch (e) {
      console.error('导入图集图片失败:', e);
      promptAction.showToast({ message: '导入图片失败' });
    }
  }

  async pickAlbumZip(): Promise<void> {
    const album = this.getSelectedAlbum();
    if (!album) {
      promptAction.showToast({ message: '请先选择或新建图集' });
      return;
    }
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['ZIP 压缩包|.zip'];
      options.maxSelectNumber = 1;
      const result = await new picker.DocumentViewPicker(getContext(this)).select(options);
      if (!result || result.length === 0) {
        return;
      }
      const imagePaths = await this.extractImagesFromZip(result[0]);
      if (imagePaths.length === 0) {
        promptAction.showToast({ message: '压缩包中未找到图片' });
        return;
      }
      await this.addCoversToAlbum(album.id, imagePaths);
      promptAction.showToast({ message: `已从压缩包导入 ${imagePaths.length} 张图片` });
    } catch (e) {
      console.error('导入图集压缩包失败:', e);
      promptAction.showToast({ message: '读取压缩包失败' });
    }
  }

  async exportSelectedAlbumZip(): Promise<void> {
    const album = this.getSelectedAlbum();
    if (!album) {
      promptAction.showToast({ message: '请先选择或新建图集' });
      return;
    }
    if (album.covers.length === 0) {
      promptAction.showToast({ message: '当前图集还没有图片' });
      return;
    }
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`${this.safeFileName(album.name)}.zip`];
      options.fileSuffixChoices = ['ZIP 压缩包|.zip'];
      const result = await new picker.DocumentViewPicker(getContext(this)).save(options);
      if (!result || result.length === 0) {
        return;
      }
      promptAction.showToast({ message: '正在导出图集...' });
      const exportResult = await this.createAlbumZip(album);
      await fs.copy(fileUri.getUriFromPath(exportResult.zipPath), result[0]);
      promptAction.showToast({ message: `已导出 ${exportResult.imageCount} 张图片` });
    } catch (e) {
      console.error('导出图集压缩包失败:', e);
      promptAction.showToast({ message: '导出 ZIP 失败' });
    }
  }

  async addCoversToAlbum(albumId: string, sourceUris: string[]): Promise<void> {
    const context = getContext(this);
    const dir = `${context.filesDir}/cover_albums/${albumId}`;
    await this.ensureDir(dir);
    const savedUris: string[] = [];
    for (let i = 0; i < sourceUris.length; i++) {
      const source = sourceUris[i];
      if (!source) {
        continue;
      }
      const destPath = `${dir}/${Date.now()}_${i}${this.coverExt(source)}`;
      const destUri = fileUri.getUriFromPath(destPath);
      try {
        const copySource = source.startsWith('/') ? fileUri.getUriFromPath(source) : source;
        await fs.copy(copySource, destUri);
        savedUris.push(destUri);
      } catch (e) {
        console.warn('复制图集图片失败，使用原始路径:', e);
        savedUris.push(source.startsWith('/') ? fileUri.getUriFromPath(source) : source);
      }
    }
    if (savedUris.length === 0) {
      return;
    }
    const next = this.albums.map((album: CoverAlbum) => {
      if (album.id === albumId) {
        const item = new CoverAlbum();
        item.id = album.id;
        item.name = album.name;
        item.covers = [...album.covers, ...savedUris];
        return item;
      }
      return album;
    });
    this.saveAlbums(next, albumId);
  }

  async createAlbumZip(album: CoverAlbum): Promise<CoverGalleryExportResult> {
    const context = getContext(this);
    const safeName = this.safeFileName(album.name);
    const exportRoot = `${context.tempDir}/album_export_${Date.now()}`;
    const imageDir = `${exportRoot}/${safeName}`;
    const zipPath = `${exportRoot}/${safeName}.zip`;
    await this.ensureDir(exportRoot);
    await this.ensureDir(imageDir);

    let copiedCount = 0;
    for (let i = 0; i < album.covers.length; i++) {
      const source = album.covers[i];
      if (!source) {
        continue;
      }
      const fileName = `${this.padIndex(i + 1, album.covers.length)}${this.coverExt(source)}`;
      const destPath = `${imageDir}/${fileName}`;
      try {
        const copySource = source.startsWith('/') ? fileUri.getUriFromPath(source) : source;
        await fs.copy(copySource, fileUri.getUriFromPath(destPath));
        copiedCount++;
      } catch (e) {
        console.warn('复制待导出的图集图片失败:', e);
      }
    }
    if (copiedCount === 0) {
      throw new Error('no images copied');
    }

    await zlib.compressFile(imageDir, zipPath, {});
    const result = new CoverGalleryExportResult();
    result.zipPath = zipPath;
    result.imageCount = copiedCount;
    return result;
  }

  async extractImagesFromZip(zipUri: string): Promise<string[]> {
    const context = getContext(this);
    const zipDir = `${context.tempDir}/album_zip_${Date.now()}`;
    const zipPath = `${zipDir}/source.zip`;
    const outDir = `${zipDir}/out`;
    await this.ensureDir(zipDir);
    await this.ensureDir(outDir);
    await fs.copy(zipUri, fileUri.getUriFromPath(zipPath));
    await zlib.decompressFile(zipPath, outDir);
    return await this.findImages(outDir);
  }

  async findImages(dir: string): Promise<string[]> {
    const images: string[] = [];
    let names: string[] = [];
    try {
      names = await fs.listFile(dir);
    } catch (e) {
      return images;
    }
    names.sort();
    for (const name of names) {
      const path = `${dir}/${name}`;
      const stat = await fs.stat(path);
      if (stat.isDirectory()) {
        images.push(...await this.findImages(path));
      } else if (this.isImageFile(name)) {
        images.push(path);
      }
    }
    return images;
  }

  async ensureDir(path: string): Promise<void> {
    try {
      await fs.mkdir(path, true);
    } catch (e) {
    }
  }

  coverExt(value: string): string {
    const lower = value.toLowerCase();
    if (lower.includes('.png')) return '.png';
    if (lower.includes('.webp')) return '.webp';
    if (lower.includes('.bmp')) return '.bmp';
    if (lower.includes('.gif')) return '.gif';
    return '.jpg';
  }

  safeFileName(value: string): string {
    const name = value.trim().replace(/[\\/:*?"<>|]/g, '_');
    return name.length > 0 ? name : 'cover_album';
  }

  padIndex(index: number, total: number): string {
    const width = `${total}`.length;
    let value = `${index}`;
    while (value.length < width) {
      value = `0${value}`;
    }
    return value;
  }

  isImageFile(name: string): boolean {
    const lower = name.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
      lower.endsWith('.webp') || lower.endsWith('.bmp') || lower.endsWith('.gif');
  }

  hideKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
    }
  }

  getSelectedAlbumCovers(): string[] {
    const album = this.getSelectedAlbum();
    return album ? [...album.covers] : [];
  }

  totalCoverCount(): number {
    let count = 0;
    for (const album of this.albums) {
      count += album.covers.length;
    }
    return count;
  }

  selectedAlbumName(): string {
    const album = this.getSelectedAlbum();
    return album ? album.name : '未选择';
  }

  selectedAlbumCoverCount(): number {
    const album = this.getSelectedAlbum();
    return album ? album.covers.length : 0;
  }

  currentAlbumCount(): number {
    return this.albums.length;
  }

  refreshAlbumStats(albums: CoverAlbum[] = this.albums, selectedAlbumId: string = this.selectedAlbumId): void {
    let count = 0;
    for (const album of albums) {
      count += album.covers.length;
    }
    this.albumCount = albums.length;
    this.totalCoverSize = count;
    const album = CoverGallerySettings.getAlbum(albums, selectedAlbumId);
    this.selectedAlbumCoverSize = album ? album.covers.length : 0;
  }

  hasAlbumPayload(raw: string): boolean {
    return (raw || '').trim().length > 0;
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F0F2F5';
  }

  selectedColor(): string {
    return this.appDarkMode ? '#12304D' : '#E8F2FF';
  }

  accentColor(): string {
    return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  buttonColor(): string {
    return this.appDarkMode ? this.appDarkButtonColor : this.appLightButtonColor;
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#888';
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleBar() {
    Row() {
      Text('<')
        .fontSize(24)
        .fontColor(this.primaryTextColor())
        .width(40)
        .height(56)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          AppStorage.setOrCreate('coverGalleryUpdateTime', Date.now());
          router.back();
        })
      Text('封面图集')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())

      Text(`${this.albumCount} 个图集`)
        .fontSize(13)
        .fontColor('#FFFFFF')
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor(this.accentColor())
        .margin({ left: 10 })

      Blank()
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }

  @Builder
  summaryPanel() {
    Column({ space: 14 }) {
      Text(`当前：${this.selectedAlbumName()}`)
        .fontSize(13)
        .fontColor(this.subTextColor())
        .width('100%')

      Row({ space: 8 }) {
        Column() {
          Text(`${this.totalCoverSize}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text('图片总数')
            .fontSize(12)
            .fontColor(this.subTextColor())
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .padding({ top: 12, bottom: 12 })
        .borderRadius(8)
        .backgroundColor(this.inputColor())

        Column() {
          Text(`${this.selectedAlbumCoverSize}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text('当前图集')
            .fontSize(12)
            .fontColor(this.subTextColor())
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .padding({ top: 12, bottom: 12 })
        .borderRadius(8)
        .backgroundColor(this.inputColor())
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 18 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  statBlock(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Text(label)
        .fontSize(12)
        .fontColor(this.subTextColor())
        .margin({ top: 3 })
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(8)
    .backgroundColor(this.inputColor())
  }

  @Builder
  albumSectionTitle() {
    Row({ space: 8 }) {
      Text('图集')
        .fontSize(13)
        .fontColor(this.subTextColor())

      Button('新建')
        .height(28)
        .width(64)
        .fontSize(13)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.newAlbumName = '';
          this.showCreateAlbumDialog = true;
        })

      Blank()
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  albumListPanel() {
    if (this.albums.length > 0) {
      Column({ space: 10 }) {
        ForEach(this.albums, (album: CoverAlbum) => {
          this.albumRow(album)
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(this.cardColor())
    } else {
      Column() {
        Text('暂无图集')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text('新建图集后，可上传图片或 ZIP 压缩包。')
          .fontSize(13)
          .fontColor(this.subTextColor())
          .margin({ top: 6 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 26, bottom: 26 })
      .backgroundColor(this.cardColor())
    }
  }

  @Builder
  albumRow(album: CoverAlbum) {
    Row({ space: 12 }) {
      this.albumThumb(album)

      Column() {
        Text(album.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${album.covers.length} 张图片`)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.selectedAlbumId === album.id) {
        Text('已选')
          .fontSize(12)
          .fontColor(this.accentColor())
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(5)
          .backgroundColor(this.selectedColor())
      } else {
        Text('选择')
          .fontSize(12)
          .fontColor(this.subTextColor())
      }
    }
    .width('100%')
    .height(78)
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .backgroundColor(this.selectedAlbumId === album.id ? this.selectedColor() : this.inputColor())
    .onClick(() => {
      this.selectAlbum(album);
    })
  }

  @Builder
  albumThumb(album: CoverAlbum) {
    Stack() {
      Column()
        .width(42)
        .height(56)
        .borderRadius(6)
        .backgroundColor(this.appDarkMode ? '#30343C' : '#E6EAF0')

      if (album.covers.length > 0) {
        Image(album.covers[0])
          .width(42)
          .height(56)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
      } else {
        Text('封')
          .fontSize(18)
          .fontColor(this.subTextColor())
      }
    }
    .width(42)
    .height(56)
  }

  @Builder
  selectedAlbumPanel() {
    Column({ space: 14 }) {
      Column() {
        TextInput({ placeholder: '重命名图集', text: this.renameAlbumName })
          .height(42)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(8)
          .onChange((value: string) => {
            this.renameAlbumName = value;
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        this.actionButton('重命名', this.buttonColor(), () => this.renameSelectedAlbum())
        this.actionButton('上传图片', this.buttonColor(), () => this.pickAlbumImages())
        this.actionButton('上传 ZIP', this.buttonColor(), () => this.pickAlbumZip())
      }

      Row({ space: 8 }) {
        this.actionButton('导出 ZIP', this.buttonColor(), () => this.exportSelectedAlbumZip())
        this.actionButton('管理图片', this.buttonColor(), () => this.openImageManager())
        this.actionButton('删除图集', '#E53935', () => this.requestDeleteSelectedAlbum())
      }

      this.albumPreview()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  actionButton(title: string, color: string, action: () => void) {
    Button(title)
      .fontSize(13)
      .fontColor('#FFFFFF')
      .height(38)
      .layoutWeight(1)
      .borderRadius(8)
      .backgroundColor(color)
      .onClick(action)
  }

  @Builder
  albumPreview() {
    if (this.getSelectedAlbumCovers().length > 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.getSelectedAlbumCovers(), (cover: string) => {
          Image(cover)
            .width(58)
            .height(78)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
            .margin({ right: 8, bottom: 8 })
        })
      }
      .width('100%')
    } else {
      Text('当前图集还没有图片。')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .width('100%')
      .padding({ top: 8, bottom: 4 })
    }
  }

  @Builder
  createAlbumDialog() {
    Column() {
      Column({ space: 14 }) {
        Text('新建图集')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)

        TextInput({ placeholder: '输入图集名称', text: this.newAlbumName })
          .height(44)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(8)
          .onChange((value: string) => {
            this.newAlbumName = value;
          })

        Row({ space: 10 }) {
          Button('取消')
            .height(42)
            .layoutWeight(1)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.newAlbumName = '';
              this.showCreateAlbumDialog = false;
              this.hideKeyboard();
            })
          Button('新建')
            .height(42)
            .layoutWeight(1)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.createAlbum();
            })
        }
        .width('100%')
      }
      .width('84%')
      .padding(20)
      .borderRadius(12)
      .backgroundColor(this.cardColor())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  deleteAlbumConfirmDialog() {
    Column() {
      Column({ space: 14 }) {
        Text('删除图集')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)

        Text(`确定删除《${this.selectedAlbumName()}》吗？`)
          .fontSize(14)
          .fontColor(this.subTextColor())
          .lineHeight(22)
          .width('100%')
          .textAlign(TextAlign.Center)

        Row({ space: 10 }) {
          Button('取消')
            .height(42)
            .layoutWeight(1)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.showDeleteAlbumConfirm = false;
            })
          Button('删除')
            .height(42)
            .layoutWeight(1)
            .backgroundColor('#E53935')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.deleteSelectedAlbum();
            })
        }
        .width('100%')
      }
      .width('84%')
      .padding(20)
      .borderRadius(12)
      .backgroundColor(this.cardColor())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  imageManagerDialog() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Column() {
            Text('管理图片')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
            Text(`${this.selectedAlbumCoverSize} 张图片，已选 ${this.selectedImages.length} 张`)
              .fontSize(12)
              .fontColor(this.subTextColor())
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button('关闭')
            .height(34)
            .fontSize(13)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.closeImageManager();
            })
        }
        .width('100%')

        Row({ space: 8 }) {
          this.imageManageButton('全选', this.buttonColor(), () => this.selectAllImages())
          this.imageManageButton('取消选择', '#60656F', () => this.clearImageSelection())
          this.imageManageButton('删除所选', '#E53935', () => this.deleteSelectedImages())
        }
        .width('100%')

        if (this.getSelectedAlbumCovers().length > 0) {
          Scroll() {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.getSelectedAlbumCovers(), (cover: string) => {
                this.imageEditItem(cover)
              }, (cover: string) => cover)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Auto)
        } else {
          Column() {
            Text('当前图集还没有图片。')
              .fontSize(14)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .height(180)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('92%')
      .height('78%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.cardColor())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  imageManageButton(title: string, color: string, action: () => void) {
    Button(title)
      .height(36)
      .fontSize(12)
      .layoutWeight(1)
      .fontColor('#FFFFFF')
      .backgroundColor(color)
      .borderRadius(8)
      .onClick(action)
  }

  @Builder
  imageEditItem(cover: string) {
    Stack() {
      Image(cover)
        .width(66)
        .height(88)
        .objectFit(ImageFit.Cover)
        .borderRadius(6)

      if (this.isImageSelected(cover)) {
        Column() {
          Text('✓')
            .fontSize(24)
            .fontColor('#FFFFFF')
        }
        .width(66)
        .height(88)
        .borderRadius(6)
        .backgroundColor('#66007DFF')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width(66)
    .height(88)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      this.toggleImageSelection(cover);
    })
  }
}
