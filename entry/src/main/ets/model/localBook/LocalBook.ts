import { Book, BookChapter } from '../data/Book';
import { appDb } from '../data/AppDatabase';
import fs from '@ohos.file.fs';

export class LocalBook {
  static async importBook(filePath: string): Promise<Book | null> {
    try {
      const fileName = filePath.split('/').pop() || '';
      const book = new Book();
      book.bookUrl = filePath;
      book.name = fileName.replace(/\.[^.]+$/, '');
      book.origin = 'local';
      book.originName = fileName;
      book.author = '未知';
      
      // 检查是否已存在
      const existing = await appDb.getBook(book.bookUrl);
      if (existing) {
        return existing;
      }
      
      // 解析书籍
      const ext = fileName.split('.').pop()?.toLowerCase();
      switch (ext) {
        case 'txt':
          await TextFile.parse(book);
          break;
        case 'epub':
          await EpubFile.parse(book);
          break;
        case 'umd':
          await UmdFile.parse(book);
          break;
        default:
          throw new Error('不支持的格式');
      }
      
      // 保存书籍
      await appDb.insertBook(book);
      
      return book;
    } catch (e) {
      console.error('导入书籍失败:', e);
      return null;
    }
  }

  static async getChapterContent(book: Book, chapter: BookChapter): Promise<string> {
    try {
      const ext = book.originName.split('.').pop()?.toLowerCase();
      switch (ext) {
        case 'txt':
          return await TextFile.getContent(book, chapter);
        case 'epub':
          return await EpubFile.getContent(book, chapter);
        case 'umd':
          return await UmdFile.getContent(book, chapter);
        default:
          return '';
      }
    } catch (e) {
      console.error('获取章节内容失败:', e);
      return '';
    }
  }
}

export class TextFile {
  private static readonly CHAPTER_PATTERNS = [
    /^第[零一二三四五六七八九十百千万\d]+[章节回集卷部篇幕].*/gm,
    /^Chapter\s+\d+.*/gim,
    /^卷\d+.*/gm,
    /^【.*】.*/gm,
    /^正文.*/gm
  ];

  static async parse(book: Book): Promise<void> {
    const filePath = book.bookUrl;
    
    try {
      // 读取文件内容
      const stat = await fs.stat(filePath);
      const file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      
      // 检测编码
      const charset = await this.detectCharset(file);
      book.charset = charset;
      
      // 读取前10KB用于章节检测
      const buffer = new ArrayBuffer(10240);
      await fs.read(file.fd, buffer);
      const preview = this.arrayBufferToString(buffer, charset);
      
      // 检测章节
      const chapters = this.detectChapters(preview, stat.size);
      
      if (chapters.length > 0) {
        book.totalChapterNum = chapters.length;
        
        // 保存章节信息
        const bookChapters: BookChapter[] = [];
        for (let i = 0; i < chapters.length; i++) {
          const chapter = new BookChapter();
          chapter.url = `${book.bookUrl}#${chapters[i].start}`;
          chapter.title = chapters[i].title;
          chapter.bookUrl = book.bookUrl;
          chapter.index = i;
          chapter.start = chapters[i].start;
          chapter.end = chapters[i].end;
          bookChapters.push(chapter);
        }
        
        await appDb.deleteBookChapters(book.bookUrl);
        await appDb.insertBookChapters(bookChapters);
      }
      
      await fs.close(file);
    } catch (e) {
      console.error('解析TXT失败:', e);
      throw e;
    }
  }

  static async getContent(book: Book, chapter: BookChapter): Promise<string> {
    try {
      const file = await fs.open(book.bookUrl, fs.OpenMode.READ_ONLY);
      const length = chapter.end - chapter.start;
      const buffer = new ArrayBuffer(length);
      
      await fs.read(file.fd, buffer, { offset: chapter.start, length: length });
      await fs.close(file);
      
      return this.arrayBufferToString(buffer, book.charset || 'UTF-8');
    } catch (e) {
      console.error('读取TXT内容失败:', e);
      return '';
    }
  }

  private static async detectCharset(file: fs.File): Promise<string> {
    // 简化实现，实际需要检测BOM和编码
    return 'UTF-8';
  }

  private static detectChapters(content: string, fileSize: number): Array<{title: string, start: number, end: number}> {
    const chapters: Array<{title: string, start: number, end: number}> = [];
    
    // 尝试使用各种模式匹配章节
    for (const pattern of this.CHAPTER_PATTERNS) {
      const matches = Array.from(content.matchAll(pattern));
      if (matches.length >= 2) {
        for (let i = 0; i < matches.length; i++) {
          const start = matches[i].index || 0;
          const end = i < matches.length - 1 ? (matches[i + 1].index || fileSize) : fileSize;
          chapters.push({
            title: matches[i][0].trim(),
            start: start,
            end: end
          });
        }
        break;
      }
    }
    
    // 如果没有检测到章节，按固定大小分割
    if (chapters.length === 0) {
      const chapterSize = 50000; // 每章50KB
      const count = Math.ceil(fileSize / chapterSize);
      for (let i = 0; i < count; i++) {
        chapters.push({
          title: `第${i + 1}章`,
          start: i * chapterSize,
          end: Math.min((i + 1) * chapterSize, fileSize)
        });
      }
    }
    
    return chapters;
  }

  private static arrayBufferToString(buffer: ArrayBuffer, charset: string): string {
    const decoder = new util.TextDecoder(charset);
    return decoder.decode(new Uint8Array(buffer));
  }
}

export class EpubFile {
  static async parse(book: Book): Promise<void> {
    try {
      // EPUB解析需要专门的库
      // 这里提供基本框架
      
      book.type = 1; // BOOK_TYPE_EPUB
      
      // 读取META-INF/container.xml获取OPF路径
      // 解析OPF获取书籍信息和章节列表
      // 解析NCX获取目录结构
      
      console.log('EPUB解析需要专门的库支持');
    } catch (e) {
      console.error('解析EPUB失败:', e);
      throw e;
    }
  }

  static async getContent(book: Book, chapter: BookChapter): Promise<string> {
    try {
      // 从EPUB中读取章节内容
      // 需要解压EPUB文件并读取对应的HTML文件
      
      return '';
    } catch (e) {
      console.error('读取EPUB内容失败:', e);
      return '';
    }
  }
}

export class UmdFile {
  static async parse(book: Book): Promise<void> {
    try {
      // UMD解析需要专门的库
      // 这里提供基本框架
      
      book.type = 2; // BOOK_TYPE_UMD
      
      console.log('UMD解析需要专门的库支持');
    } catch (e) {
      console.error('解析UMD失败:', e);
      throw e;
    }
  }

  static async getContent(book: Book, chapter: BookChapter): Promise<string> {
    try {
      // 从UMD中读取章节内容
      
      return '';
    } catch (e) {
      console.error('读取UMD内容失败:', e);
      return '';
    }
  }
}

export class TextChapter {
  title: string = '';
  start: number = 0;
  end: number = 0;
}