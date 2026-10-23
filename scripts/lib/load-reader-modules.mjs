// 把 entry 下与系统 API 无关的纯 TS 阅读器模块加载进 Node。
// node --experimental-strip-types 要求相对 import 带扩展名，而应用代码遵循 ArkTS 惯例不带后缀：
// 这里把文件拷到临时目录并补上 '.ts' 后再加载，应用源码保持规范写法不变。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { ETS_ROOTS, readEtsModule, toNodeModuleSource } from './ets-module-staging.mjs';

const MODULES = [
  'core/book/ReaderImageMarker.ts',
  'core/book/ReaderActionMarker.ts',
  'core/book/EpubHtmlConverter.ts',
  'core/book/EpubChapterPlanner.ts',
  'core/book/ReaderCacheBudgetPolicy.ts',
  'core/book/MobiBookParser.ts',
  'core/reader/ReaderMixedPageLayout.ts',
  'core/reader/ReaderTextNormalizer.ts',
  'core/reader/ReaderParagraphIndent.ts',
  'core/reader/ReaderPageOffsets.ts',
  'core/reader/ReaderChunkPagination.ts',
  'core/reader/ReaderChapterRange.ts',
  'core/reader/ReaderPageTurnQueue.ts',
  'core/reader/ReaderInfoBarModel.ts',
];

export async function loadReaderModules() {
  const stagingDir = fs.mkdtempSync(path.join(os.tmpdir(), 'reader-modules-check-'));
  const cleanup = () => fs.rmSync(stagingDir, { recursive: true, force: true });
  try {
    const exported = {};
    for (const relative of MODULES) {
      if (!ETS_ROOTS.some((root) => fs.existsSync(path.join(root, relative)))) continue;
      const target = path.join(stagingDir, relative);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      const text = toNodeModuleSource(readEtsModule(relative), relative);
      fs.writeFileSync(target, text);
    }
    for (const relative of MODULES) {
      const target = path.join(stagingDir, relative);
      if (!fs.existsSync(target)) continue;
      Object.assign(exported, await import(pathToFileURL(target).href));
    }
    return { ...exported, cleanup };
  } catch (error) {
    cleanup();
    throw error;
  }
}
