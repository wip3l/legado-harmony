#!/usr/bin/env node
// 正文/漫画缓存容量清理计划的回归检查：超限才清、按最久未用删到 90%、保护项跳过、手动清理保留使用中的条目。
// 直接加载 entry 下的 ReaderCacheBudgetPolicy.ts；数据库与文件的实际删除在真机上验证。
// Usage: node --experimental-strip-types scripts/reader-cache-budget-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { CacheBudgetItem, ReaderCacheBudgetPolicy, cleanup } = await loadReaderModules();

let failures = 0;
const check = (condition, message, detail = '') => {
  if (condition) {
    console.log(`  ok - ${message}`);
  } else {
    failures++;
    console.error(`  FAIL - ${message}${detail ? `\n         ${detail}` : ''}`);
  }
};
const equal = (actual, expected, message) =>
  check(JSON.stringify(actual) === JSON.stringify(expected), message,
    `expected ${JSON.stringify(expected)}\n         actual   ${JSON.stringify(actual)}`);

const item = (id, bytes, usedAt, owner = '') => {
  const value = new CacheBudgetItem();
  value.id = id;
  value.bytes = bytes;
  value.usedAt = usedAt;
  value.owner = owner;
  return value;
};
const never = () => false;

try {
  console.log('planTrim');
  {
    const items = [item('a', 40, 1), item('b', 40, 2)];
    const plan = ReaderCacheBudgetPolicy.planTrim(items, 100, 100, never);
    equal(plan.removeIds, [], '未超过上限时不清理');
    equal(plan.remainingBytes, 100, '未超限时剩余量等于总量');
  }
  {
    // 上限 100，目标 90；总量 130，需要释放 40 以上。
    const items = [item('new', 30, 300), item('old', 30, 100), item('mid', 30, 200), item('older', 20, 50)];
    const plan = ReaderCacheBudgetPolicy.planTrim(items, 130, 100, never);
    equal(plan.removeIds, ['older', 'old'], '按最久未用的先删，删到上限的 90%');
    equal(plan.releasedBytes, 50, '释放量是被删条目之和');
    equal(plan.remainingBytes, 80, '剩余量扣掉释放量');
  }
  {
    const items = [item('a', 30, 1, 'reading'), item('b', 30, 2), item('c', 30, 3)];
    const plan = ReaderCacheBudgetPolicy.planTrim(items, 130, 100, (value) => value.owner === 'reading');
    equal(plan.removeIds, ['b', 'c'], '正在阅读的书跳过，继续删后面的');
    equal(plan.protectedCount, 1, '记下保留数量');
  }
  {
    // 手动缓存不在 items 里但计入总量：自动缓存删光也降不到目标，不能误删别的东西。
    const items = [item('auto', 10, 1)];
    const plan = ReaderCacheBudgetPolicy.planTrim(items, 300, 100, never);
    equal(plan.removeIds, ['auto'], '只删可清理条目，手动缓存超额时自动缓存全部删掉为止');
    equal(plan.remainingBytes, 290, '剩余量仍包含手动缓存');
  }
  {
    const items = [item('a', 60, 1), item('b', 60, 2)];
    const plan = ReaderCacheBudgetPolicy.planTrim(items, 120, 100, () => true);
    equal(plan.removeIds, [], '全部在保护期内时不删');
    equal(plan.protectedCount, 2, '保护数量计全');
  }

  console.log('planClear');
  {
    const items = [item('a', 10, 1, 'x'), item('b', 20, 2, 'reading'), item('c', 30, 3, 'y')];
    const plan = ReaderCacheBudgetPolicy.planClear(items, (value) => value.owner === 'reading');
    equal(plan.removeIds, ['a', 'c'], '手动清理删掉除使用中以外的全部条目');
    equal(plan.releasedBytes, 40, '手动清理的释放量');
    equal(plan.protectedCount, 1, '手动清理记下保留数量');
    equal(plan.remainingBytes, 20, '手动清理后剩下使用中的条目');
  }

  console.log('formatBytes');
  equal(ReaderCacheBudgetPolicy.formatBytes(0), '0 B', '0 字节');
  equal(ReaderCacheBudgetPolicy.formatBytes(1536), '1.5 KiB', 'KiB 保留一位小数');
  equal(ReaderCacheBudgetPolicy.formatBytes(256 * 1024 * 1024), '256 MiB', '整百以上不带小数');
  equal(ReaderCacheBudgetPolicy.formatBytes(1024 * 1024 * 1024), '1 GiB', '去掉多余的 .0');
  equal(ReaderCacheBudgetPolicy.formatBytes(-5), '0 B', '负数按 0 显示');
} finally {
  cleanup();
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall reader cache budget checks passed');
