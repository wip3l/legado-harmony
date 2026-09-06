import assert from 'node:assert/strict';
import test from 'node:test';

process.env.DATABASE_URL ||= 'postgresql://test:test@127.0.0.1:5432/test';
process.env.SESSION_SECRET ||= 'test-session-secret-that-is-long-enough';
process.env.HUAWEI_CLIENT_ID ||= 'test-client';
process.env.HUAWEI_CLIENT_SECRET ||= 'test-secret';
process.env.HUAWEI_APP_ID ||= 'test-app';
process.env.HUAWEI_IAP_KEY_ID ||= 'test-key';
process.env.HUAWEI_IAP_ISSUER_ID ||= 'test-issuer';
process.env.HUAWEI_IAP_PRIVATE_KEY_PATH ||= 'test-private-key.pem';
process.env.HUAWEI_IAP_ROOT_CA_PATH ||= 'test-root-ca.pem';
process.env.HUAWEI_IAP_ROOT_URL ||= 'https://example.com';
process.env.HUAWEI_IAP_DELIVERABLE_STATUSES ||= '0,PAID';

const {
  calculateNextSyncQuota,
  ensureSyncQuota,
  normalizeOperation,
  SyncApiError
} = await import('./sync.js');

const OP_ID = '123e4567-e89b-42d3-a456-426614174000';

test('book source payloads may exceed the default 64KB limit', () => {
  const normalized = normalizeOperation({
    opId: OP_ID,
    entityType: 'book_source',
    entityId: 'source_test',
    operation: 'upsert',
    baseRevision: 0,
    payload: { rules: 'x'.repeat(96 * 1024) }
  });
  assert.equal(normalized.entityType, 'book_source');
});

test('non-book-source payloads keep the 64KB limit', () => {
  assert.throws(() => normalizeOperation({
    opId: OP_ID,
    entityType: 'reader_settings',
    entityId: 'global',
    operation: 'upsert',
    baseRevision: 0,
    payload: { settings: 'x'.repeat(96 * 1024) }
  }), (error: unknown) =>
    error instanceof SyncApiError &&
    error.statusCode === 413 &&
    error.code === 'SYNC_PAYLOAD_TOO_LARGE');
});

test('local reading progress payloads remain metadata-only JSON', () => {
  const normalized = normalizeOperation({
    opId: OP_ID,
    entityType: 'reading_progress',
    entityId: 'book_local_content_fingerprint',
    operation: 'upsert',
    baseRevision: 0,
    payload: {
      origin: 'local',
      localContentHash: 'a'.repeat(64),
      chapterTitle: '第一章',
      chapterIndex: 3,
      chapterPos: 2,
      updatedAt: Date.now()
    }
  });
  assert.equal(normalized.entityType, 'reading_progress');
  assert.equal((normalized.payload as { localContentHash: string }).localContentHash.length, 64);
});

test('book source payloads up to 512KB are accepted', () => {
  assert.doesNotThrow(() => normalizeOperation({
    opId: OP_ID,
    entityType: 'book_source',
    entityId: 'source_test',
    operation: 'upsert',
    baseRevision: 0,
    payload: { rules: 'x'.repeat(511 * 1024) }
  }));
});

test('book source payloads cannot exceed 512KB', () => {
  assert.throws(() => normalizeOperation({
    opId: OP_ID,
    entityType: 'book_source',
    entityId: 'source_test',
    operation: 'upsert',
    baseRevision: 0,
    payload: { rules: 'x'.repeat(513 * 1024) }
  }), (error: unknown) =>
    error instanceof SyncApiError &&
    error.statusCode === 413 &&
    error.code === 'SYNC_PAYLOAD_TOO_LARGE');
});

test('sync quotas reject unbounded daily writes and storage growth', () => {
  assert.throws(() => ensureSyncQuota({
    entityCount: 1,
    entityBytes: 1,
    changeCount: 1,
    changeBytes: 1,
    dailyWrites: 5001
  }), (error: unknown) => error instanceof SyncApiError && error.code === 'SYNC_DAILY_WRITE_LIMITED');
  assert.throws(() => ensureSyncQuota({
    entityCount: 20_001,
    entityBytes: 1,
    changeCount: 1,
    changeBytes: 1,
    dailyWrites: 1
  }), (error: unknown) => error instanceof SyncApiError && error.code === 'SYNC_STORAGE_QUOTA_EXCEEDED');
});

test('initial sync window allows a one-time 20000-write import', () => {
  assert.doesNotThrow(() => ensureSyncQuota({
    entityCount: 19_000,
    entityBytes: 1,
    changeCount: 19_000,
    changeBytes: 1,
    dailyWrites: 20_000,
    initialSyncActive: true
  }));
  assert.throws(() => ensureSyncQuota({
    entityCount: 19_000,
    entityBytes: 1,
    changeCount: 19_000,
    changeBytes: 1,
    dailyWrites: 20_001,
    initialSyncActive: true
  }), (error: unknown) => error instanceof SyncApiError && error.code === 'SYNC_DAILY_WRITE_LIMITED');
});

test('updating an entity reuses its lightweight change marker', () => {
  assert.deepEqual(calculateNextSyncQuota({
    entityCount: 10,
    entityBytes: 1000,
    changeCount: 10,
    changeBytes: 0,
    dailyWrites: 2
  }, true, 100, 250), {
    entityCount: 10,
    entityBytes: 1150,
    changeCount: 10,
    changeBytes: 0,
    dailyWrites: 3,
    initialSyncActive: undefined
  });
});

test('creating an entity adds exactly one lightweight change marker', () => {
  assert.deepEqual(calculateNextSyncQuota({
    entityCount: 10,
    entityBytes: 1000,
    changeCount: 10,
    changeBytes: 0,
    dailyWrites: 2,
    initialSyncActive: true
  }, false, 0, 250), {
    entityCount: 11,
    entityBytes: 1250,
    changeCount: 11,
    changeBytes: 0,
    dailyWrites: 3,
    initialSyncActive: true
  });
});
