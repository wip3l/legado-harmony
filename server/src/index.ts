import Fastify, { FastifyReply, FastifyRequest } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { jwtVerify } from 'jose';
import { Buffer } from 'node:buffer';
import { createHash, randomUUID } from 'node:crypto';
import { gzip as gzipCallback, constants as zlibConstants } from 'node:zlib';
import { PoolClient } from 'pg';
import { config } from './config.js';
import { inTransaction, pool } from './db.js';
import {
  HuaweiSisError,
  isHuaweiSisConfigured,
  SisTimedSynthesizeResult,
  synthesizeTimedWithHuaweiSis,
  synthesizeWithHuaweiSis
} from './huaweiSis.js';
import { exchangeHuaweiAuthorizationCode } from './huaweiAccount.js';
import { pointsForProduct, purchaseState, verifyPurchaseData } from './iap.js';
import {
  TTS_PACKAGES,
  TTS_PREMIUM_TRIAL_CHARS,
  TTS_STANDARD_TRIAL_CHARS,
  TTS_TRIAL_VALID_DAYS,
  TTS_TRIAL_VERSION,
  TTS_VOICES,
  TtsTier,
  chargedTtsCharacters,
  countTtsCharacters,
  findTtsVoice,
  findTtsPackage
} from './tts.js';
import {
  TtsQuotaError,
  markTtsUsageSucceeded,
  refundStaleTtsReservations,
  refundTtsUsage,
  reserveTtsUsage
} from './ttsUsage.js';
import {
  exchangeSync,
  listSyncDevices,
  renameSyncDevice,
  revokeSyncDevice,
  syncSummary,
  SyncApiError,
  SyncExchangeBody
} from './sync.js';
import {
  ByteLimitedLruCache,
  decideTtsReplay,
  TtsConcurrencyLimiter,
  TtsServerBusyError
} from './ttsRuntime.js';
import {
  encodeTimedTtsBinary,
  TIMED_TTS_BINARY_CONTENT_TYPE
} from './ttsTransport.js';
import {
  cleanupExpiredSyncReceipts,
  cleanupExpiredTtsUsage
} from './maintenance.js';
import { InvalidAvatarError, sanitizeAvatarBase64 } from './imageSecurity.js';
import { reconcileIapOrders } from './iapReconciliation.js';
import {
  AccountRateLimitError,
  cleanupExpiredSecurityRows,
  enforceAccountRateLimit
} from './security.js';
import {
  findRedeemableTheme,
  listPublishedThemes,
  themeOfferMatchesExpectation
} from './themeCatalog.js';
import {
  SESSION_AUDIENCE,
  SESSION_ISSUER,
  sessionExpiresAt,
  signSessionToken
} from './sessionTokens.js';
import { AuthBody, RedeemBody, TtsRedeemBody, TtsSynthesizeBody, IapBody, ProfileBody } from './apiModels.js';

interface AuthenticatedRequest extends FastifyRequest {
  userId?: string;
  sessionId?: string;
}

class ApiError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string
  ) {
    super(message);
  }
}

const sessionKey = new TextEncoder().encode(config.sessionSecret);
if (sessionKey.byteLength < 32) {
  throw new Error('SESSION_SECRET must contain at least 32 bytes');
}

const app = Fastify({
  logger: true,
  bodyLimit: 512 * 1024,
  trustProxy: config.http.trustedProxies
});
await app.register(rateLimit, {
  global: true,
  max: config.http.globalRateLimitPerMinute,
  timeWindow: 60_000,
  errorResponseBuilder: (_request, context) => ({
    code: 'RATE_LIMITED',
    message: '请求过于频繁，请稍后重试',
    retryAfter: context.after
  })
});
type TtsCachedResponse =
  | { kind: 'AUDIO'; audio: Buffer }
  | { kind: 'TIMED'; result: SisTimedSynthesizeResult };

const ttsAudioCache = new ByteLimitedLruCache<TtsCachedResponse>(
  config.sis.cacheMaxBytes,
  config.sis.cacheMaxEntryBytes,
  config.sis.cacheTtlMs
);
const ttsConcurrency = new TtsConcurrencyLimiter(
  config.sis.maxConcurrent,
  config.sis.maxConcurrentPerUser,
  config.sis.queueLimit,
  config.sis.queueTimeoutMs
);

app.addHook('onSend', async (request, reply, payload) => {
  reply.header('Cache-Control', 'no-store');
  reply.header('X-Content-Type-Options', 'nosniff');
  reply.header('X-Frame-Options', 'DENY');
  reply.header('Referrer-Policy', 'no-referrer');
  reply.header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  if (
    request.url.startsWith('/v1/sync/')
    && acceptsGzip(request)
    && !reply.getHeader('Content-Encoding')
    && (typeof payload === 'string' || Buffer.isBuffer(payload))
  ) {
    const source = Buffer.isBuffer(payload) ? payload : Buffer.from(payload, 'utf8');
    if (source.length >= config.sync.responseCompressionThresholdBytes) {
      const compressed = await gzipPayload(source);
      if (compressed.length < source.length) {
        reply.header('Content-Encoding', 'gzip');
        reply.header('Vary', 'Accept-Encoding');
        reply.removeHeader('Content-Length');
        return compressed;
      }
    }
  }
  return payload;
});

app.setErrorHandler((error, _request, reply) => {
  if (error instanceof ApiError) {
    void reply.status(error.statusCode).send({ code: error.code, message: error.message });
    return;
  }
  if (error instanceof SyncApiError) {
    void reply.status(error.statusCode).send({ code: error.code, message: error.message });
    return;
  }
  if (error instanceof AccountRateLimitError) {
    reply.header('Retry-After', error.retryAfterSeconds);
    void reply.status(429).send({
      code: 'RATE_LIMITED',
      message: error.message,
      retryAfter: error.retryAfterSeconds
    });
    return;
  }
  app.log.error(error);
  void reply.status(500).send({ code: 'INTERNAL_ERROR', message: '服务暂时不可用' });
});

app.get('/health', async () => ({
  ok: true,
  sisConfigured: isHuaweiSisConfigured()
}));

app.get<{ Params: { userId: string } }>('/v1/avatars/:userId', async (request, reply) => {
  const userId = request.params.userId;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) {
    throw new ApiError(404, 'AVATAR_NOT_FOUND', '头像不存在');
  }
  const result = await pool.query<{ avatar_data: Buffer; avatar_mime: string }>(
    `SELECT avatar_data, avatar_mime
     FROM app_users
     WHERE id = $1 AND avatar_data IS NOT NULL`,
    [userId]
  );
  if (!result.rowCount) {
    throw new ApiError(404, 'AVATAR_NOT_FOUND', '头像不存在');
  }
  reply.header('Content-Type', result.rows[0]!.avatar_mime || 'image/jpeg');
  reply.header('Cache-Control', 'public, max-age=86400');
  return reply.send(result.rows[0]!.avatar_data);
});

app.post<{ Body: AuthBody }>('/v1/auth/huawei', {
  bodyLimit: 16 * 1024,
  config: { rateLimit: { max: config.http.authRateLimitPerMinute, timeWindow: 60_000 } }
}, async (request) => {
  const code = request.body?.authorizationCode?.trim();
  if (!code || code.length > 4096) {
    throw new ApiError(400, 'INVALID_AUTHORIZATION_CODE', '缺少华为账号授权码');
  }
  const huaweiUser = await exchangeHuaweiAuthorizationCode(code);
  const account = await inTransaction(async (client) => {
    const userResult = await client.query<{ id: string }>(
      `INSERT INTO app_users (
         huawei_open_id, huawei_union_id, display_name, avatar_url
       ) VALUES ($1, $2, $3, $4)
       ON CONFLICT (huawei_open_id) DO UPDATE SET
         huawei_union_id = COALESCE(EXCLUDED.huawei_union_id, app_users.huawei_union_id),
         display_name = CASE
           WHEN app_users.profile_customized THEN app_users.display_name
           ELSE EXCLUDED.display_name
         END,
         avatar_url = CASE
           WHEN app_users.profile_customized THEN app_users.avatar_url
           ELSE EXCLUDED.avatar_url
         END,
         updated_at = now()
       RETURNING id`,
      [
        huaweiUser.openID,
        huaweiUser.unionID || null,
        huaweiUser.displayName || '华为用户',
        huaweiUser.headPictureURL || ''
      ]
    );
    const userId = userResult.rows[0]!.id;
    await client.query(
      `INSERT INTO point_wallets (user_id, balance, paid_balance, promo_balance)
       VALUES ($1, 0, 0, 0)
       ON CONFLICT (user_id) DO NOTHING`,
      [userId]
    );
    const wallet = await client.query<{ balance: string }>(
      'SELECT balance FROM point_wallets WHERE user_id = $1 FOR UPDATE',
      [userId]
    );
    const oldBalance = Number(wallet.rows[0]!.balance);
    const idempotencyKey = `welcome:${userId}`;
    const granted = await client.query(
       `INSERT INTO point_ledger (
          user_id, delta, balance_after, reason, reference_id, idempotency_key
        ) VALUES ($1, 300, $2, 'WELCOME_GRANT', $4, $3)
        ON CONFLICT (idempotency_key) DO NOTHING
        RETURNING id`,
      [userId, oldBalance + 300, idempotencyKey, userId]
    );
    if (granted.rowCount === 1) {
      await client.query(
        `UPDATE point_wallets
         SET balance = balance + 300,
             promo_balance = promo_balance + 300,
             updated_at = now()
         WHERE user_id = $1`,
        [userId]
      );
    }
    return snapshot(client, userId);
  });
  return {
    sessionToken: await issueSession(account.userId, request.ip),
    account
  };
});

app.post('/v1/auth/renew', { preHandler: authenticate }, async (request) => {
  const userId = requiredUserId(request);
  const sessionId = (request as AuthenticatedRequest).sessionId!;
  const requestedExpiresAt = sessionExpiresAt(config.auth.sessionTtlDays);
  const renewed = await pool.query<{ expires_at: Date }>(
    `UPDATE auth_sessions
     SET expires_at = GREATEST(expires_at, $3)
     WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL AND expires_at > now()
     RETURNING expires_at`,
    [sessionId, userId, requestedExpiresAt]
  );
  if (!renewed.rowCount) {
    throw new ApiError(401, 'SESSION_EXPIRED', '登录已过期，请重新登录');
  }
  const expiresAt = renewed.rows[0]!.expires_at;
  return {
    sessionToken: await signSessionToken(sessionKey, userId, sessionId, expiresAt),
    expiresAt: expiresAt.getTime()
  };
});

app.get('/v1/me', { preHandler: authenticate }, async (request) => {
  return snapshot(pool, requiredUserId(request));
});

app.post<{ Body: SyncExchangeBody }>(
  '/v1/sync/exchange',
  {
    preHandler: authenticate,
    bodyLimit: config.sync.requestBodyLimitBytes
  },
  async (request) => {
    const userId = requiredUserId(request);
    await enforceAccountRateLimit(
      userId,
      'sync-exchange',
      config.http.syncRateLimitPerMinute
    );
    return exchangeSync(userId, request.body);
  }
);

app.post('/v1/auth/logout', { preHandler: authenticate }, async (request, reply) => {
  const sessionId = (request as AuthenticatedRequest).sessionId!;
  await pool.query(
    'UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, now()) WHERE id = $1',
    [sessionId]
  );
  return reply.status(204).send();
});

app.post('/v1/auth/logout-all', { preHandler: authenticate }, async (request, reply) => {
  await pool.query(
    `UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, now())
     WHERE user_id = $1 AND revoked_at IS NULL`,
    [requiredUserId(request)]
  );
  return reply.status(204).send();
});

app.get('/v1/sync/devices', { preHandler: authenticate }, async (request) => {
  return listSyncDevices(requiredUserId(request));
});

app.get('/v1/sync/summary', { preHandler: authenticate }, async (request) => {
  return syncSummary(requiredUserId(request));
});

app.post<{ Params: { deviceId: string }; Body: { deviceName?: string } }>(
  '/v1/sync/devices/:deviceId/rename',
  { preHandler: authenticate },
  async (request, reply) => {
    await renameSyncDevice(
      requiredUserId(request),
      request.params.deviceId,
      request.body?.deviceName || ''
    );
    return reply.status(204).send();
  }
);

app.post<{ Params: { deviceId: string } }>(
  '/v1/sync/devices/:deviceId/revoke',
  { preHandler: authenticate },
  async (request, reply) => {
    await revokeSyncDevice(requiredUserId(request), request.params.deviceId);
    return reply.status(204).send();
  }
);

app.post<{ Body: ProfileBody }>(
  '/v1/me/profile',
  { preHandler: authenticate },
  async (request) => {
    const userId = requiredUserId(request);
    const displayName = request.body?.displayName?.trim() || '';
    if (!displayName || Array.from(displayName).length > 30 || /[\u0000-\u001f\u007f]/.test(displayName)) {
      throw new ApiError(400, 'INVALID_DISPLAY_NAME', '昵称应为 1 至 30 个字符');
    }

    const removeAvatar = request.body?.removeAvatar === true;
    const avatarBase64 = request.body?.avatarBase64?.trim() || '';
    let avatarData: Buffer | null = null;
    if (!removeAvatar && avatarBase64) {
      try {
        avatarData = await sanitizeAvatarBase64(avatarBase64);
      } catch (error) {
        if (error instanceof InvalidAvatarError) {
          throw new ApiError(400, 'INVALID_AVATAR', error.message);
        }
        throw error;
      }
    }

    await inTransaction(async (client) => {
      if (removeAvatar) {
        await client.query(
          `UPDATE app_users
           SET display_name = $2, avatar_url = '', avatar_data = NULL,
               avatar_mime = NULL, profile_customized = TRUE, updated_at = now()
           WHERE id = $1`,
          [userId, displayName]
        );
      } else if (avatarData) {
        await client.query(
          `UPDATE app_users
           SET display_name = $2, avatar_url = '', avatar_data = $3,
               avatar_mime = 'image/jpeg', profile_customized = TRUE, updated_at = now()
           WHERE id = $1`,
          [userId, displayName, avatarData]
        );
      } else {
        await client.query(
          `UPDATE app_users
           SET display_name = $2, profile_customized = TRUE, updated_at = now()
           WHERE id = $1`,
          [userId, displayName]
        );
      }
    });
    return snapshot(pool, userId);
  }
);

app.get('/v1/themes/catalog', async () => ({
  themes: await listPublishedThemes(pool)
}));

app.post<{ Params: { themeId: string }; Body: RedeemBody }>(
  '/v1/themes/:themeId/redeem',
  { preHandler: authenticate },
  async (request) => {
    const userId = requiredUserId(request);
    const themeId = request.params.themeId;
    const requestId = request.body?.requestId?.trim();
    await enforceAccountRateLimit(
      userId,
      'theme-redeem',
      config.http.sensitiveRateLimitPerMinute
    );
    if (!requestId || requestId.length > 128) {
      throw new ApiError(400, 'INVALID_REQUEST_ID', '请求标识无效');
    }
    return inTransaction(async (client) => {
      await ensureAccountNotRestricted(client, userId);
      const idempotencyKey = `theme:${userId}:${requestId}`;
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [idempotencyKey]);
      const duplicate = await client.query(
        'SELECT 1 FROM point_ledger WHERE idempotency_key = $1',
        [idempotencyKey]
      );
      if (duplicate.rowCount) {
        return snapshot(client, userId);
      }
      const theme = await findRedeemableTheme(client, themeId);
      if (!theme) {
        throw new ApiError(404, 'THEME_NOT_FOUND', '主题不存在或暂未上架');
      }
      if (!themeOfferMatchesExpectation(
        theme,
        request.body.expectedPricePoints,
        request.body.expectedValidDays
      )) {
        throw new ApiError(409, 'THEME_OFFER_CHANGED', '主题价格或有效期已更新，请确认后重试');
      }
      const wallet = await client.query<{
        balance: string;
        paid_balance: string;
        promo_balance: string;
      }>(
        `SELECT balance, paid_balance, promo_balance
         FROM point_wallets
         WHERE user_id = $1
         FOR UPDATE`,
        [userId]
      );
      if (!wallet.rowCount) {
        throw new ApiError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
      }
      const balance = Number(wallet.rows[0]!.balance);
      if (balance < theme.pricePoints) {
        throw new ApiError(409, 'INSUFFICIENT_POINTS', '点数不足，请先充值');
      }
      const promoBalance = Number(wallet.rows[0]!.promo_balance);
      const paidBalance = Number(wallet.rows[0]!.paid_balance);
      const promoSpent = Math.min(promoBalance, theme.pricePoints);
      const paidSpent = theme.pricePoints - promoSpent;
      const balanceAfter = balance - theme.pricePoints;
      await client.query(
        `UPDATE point_wallets
         SET balance = $2,
             paid_balance = $3,
             promo_balance = $4,
             updated_at = now()
         WHERE user_id = $1`,
        [userId, balanceAfter, paidBalance - paidSpent, promoBalance - promoSpent]
      );
      await client.query(
        `INSERT INTO point_ledger (
           user_id, delta, balance_after, reason, reference_id, idempotency_key
         ) VALUES ($1, $2, $3, 'THEME_REDEEM', $4, $5)`,
        [userId, -theme.pricePoints, balanceAfter, themeId, idempotencyKey]
      );
      await client.query(
        `INSERT INTO theme_entitlements (user_id, theme_id, expires_at)
         VALUES ($1, $2, now() + make_interval(days => $3))
         ON CONFLICT (user_id, theme_id) DO UPDATE SET
           expires_at = CASE
             WHEN theme_entitlements.expires_at > now()
               THEN theme_entitlements.expires_at + make_interval(days => $3)
             ELSE now() + make_interval(days => $3)
           END,
           updated_at = now()`,
        [userId, themeId, theme.validDays]
      );
      return snapshot(client, userId);
    });
  }
);

app.get('/v1/tts/catalog', async () => ({
  voices: TTS_VOICES.map(({ property: _property, ...voice }) => voice),
  packages: TTS_PACKAGES,
  trial: {
    standardChars: TTS_STANDARD_TRIAL_CHARS,
    premiumChars: TTS_PREMIUM_TRIAL_CHARS,
    validDays: TTS_TRIAL_VALID_DAYS
  }
}));

app.get('/v1/tts/wallet', { preHandler: authenticate }, async (request) => {
  const userId = requiredUserId(request);
  return inTransaction(async (client) => {
    await ensureTtsTrial(client, userId);
    return ttsWallet(client, userId);
  });
});

app.post<{ Params: { sku: string }; Body: TtsRedeemBody }>(
  '/v1/tts/packages/:sku/redeem',
  { preHandler: authenticate },
  async (request) => {
    const userId = requiredUserId(request);
    const item = findTtsPackage(request.params.sku);
    const requestId = request.body?.requestId?.trim();
    await enforceAccountRateLimit(
      userId,
      'tts-package-redeem',
      config.http.sensitiveRateLimitPerMinute
    );
    if (!item) {
      throw new ApiError(404, 'TTS_PACKAGE_NOT_FOUND', '在线朗读字数包不存在');
    }
    if (!requestId || requestId.length > 128) {
      throw new ApiError(400, 'INVALID_REQUEST_ID', '请求标识无效');
    }

    return inTransaction(async (client) => {
      await ensureAccountNotRestricted(client, userId);
      await ensureTtsTrial(client, userId);
      const idempotencyKey = `tts-package:${userId}:${requestId}`;
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [idempotencyKey]);
      const duplicate = await client.query(
        `SELECT 1
         FROM tts_package_redemptions
         WHERE user_id = $1 AND request_id = $2`,
        [userId, requestId]
      );
      if (duplicate.rowCount) {
        return {
          account: await snapshot(client, userId),
          ttsWallet: await ttsWallet(client, userId)
        };
      }

      const wallet = await client.query<{
        balance: string;
        paid_balance: string;
        promo_balance: string;
      }>(
        `SELECT balance, paid_balance, promo_balance
         FROM point_wallets
         WHERE user_id = $1
         FOR UPDATE`,
        [userId]
      );
      if (!wallet.rowCount) {
        throw new ApiError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
      }
      const paidBalance = Number(wallet.rows[0]!.paid_balance);
      if (paidBalance < item.points) {
        throw new ApiError(409, 'INSUFFICIENT_PAID_POINTS', '充值点不足，请先充值');
      }
      const balance = Number(wallet.rows[0]!.balance);
      const promoBalance = Number(wallet.rows[0]!.promo_balance);
      const balanceAfter = balance - item.points;
      await client.query(
        `UPDATE point_wallets
         SET balance = $2,
             paid_balance = $3,
             promo_balance = $4,
             updated_at = now()
         WHERE user_id = $1`,
        [userId, balanceAfter, paidBalance - item.points, promoBalance]
      );
      const pointLedger = await client.query<{ id: string }>(
        `INSERT INTO point_ledger (
           user_id, delta, balance_after, reason, reference_id, idempotency_key
         ) VALUES ($1, $2, $3, 'TTS_PACKAGE_REDEEM', $4, $5)
         RETURNING id`,
        [userId, -item.points, balanceAfter, item.sku, idempotencyKey]
      );

      await client.query(
        'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
        [`tts-quota:${userId}:${item.tier}`]
      );
      const quotaBefore = await activeTtsBalance(client, userId, item.tier);
      const quotaGrant = await client.query<{ id: string }>(
        `INSERT INTO tts_quota_grants (
           user_id, tier, source, total_chars, remaining_chars, expires_at, reference_id
         ) VALUES (
           $1, $2, 'POINT_REDEEM', $3, $3,
           now() + make_interval(days => $4), $5
         )
         RETURNING id`,
        [userId, item.tier, item.chars, item.validDays, requestId]
      );
      await client.query(
        `INSERT INTO tts_quota_ledger (
           user_id, grant_id, tier, delta_chars, balance_after,
           reason, reference_id, idempotency_key
         ) VALUES ($1, $2, $3, $4, $5, 'PACKAGE_REDEEM', $6, $7)`,
        [
          userId,
          quotaGrant.rows[0]!.id,
          item.tier,
          item.chars,
          quotaBefore + item.chars,
          item.sku,
          `${idempotencyKey}:quota`
        ]
      );
      await client.query(
        `INSERT INTO tts_package_redemptions (
           user_id, sku, tier, chars, points_spent,
           point_ledger_id, quota_grant_id, request_id
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [
          userId,
          item.sku,
          item.tier,
          item.chars,
          item.points,
          pointLedger.rows[0]!.id,
          quotaGrant.rows[0]!.id,
          requestId
        ]
      );

      return {
        account: await snapshot(client, userId),
        ttsWallet: await ttsWallet(client, userId)
      };
    });
  }
);

app.post<{ Body: TtsSynthesizeBody }>(
  '/v1/tts/synthesize',
  { preHandler: authenticate },
  async (request, reply) => {
    if (!isHuaweiSisConfigured()) {
      throw new ApiError(503, 'TTS_NOT_CONFIGURED', '在线朗读服务尚未配置');
    }
    const userId = requiredUserId(request);
    await enforceAccountRateLimit(
      userId,
      'tts-synthesize',
      config.sis.perUserRequestsPerMinute
    );
    const requestId = request.body?.requestId?.trim() || '';
    const voiceId = request.body?.voiceId?.trim() || '';
    const text = request.body?.text?.normalize('NFC') || '';
    const voice = findTtsVoice(voiceId);
    if (!requestId || requestId.length > 128 || !/^[A-Za-z0-9._:-]+$/.test(requestId)) {
      throw new ApiError(400, 'INVALID_REQUEST_ID', '请求标识无效');
    }
    if (!voice) {
      throw new ApiError(404, 'TTS_VOICE_NOT_FOUND', '在线朗读音色不存在');
    }
    const rawChars = countTtsCharacters(text);
    if (
      rawChars <= 0
      || rawChars > 500
      || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(text)
    ) {
      throw new ApiError(400, 'INVALID_TTS_TEXT', '每段朗读文本应为 1 至 500 个字符');
    }
    const speed = integerInRange(request.body?.speed, -500, 500, 0, '语速');
    const volume = integerInRange(request.body?.volume, 0, 100, 100, '音量');
    const requestedPitch = integerInRange(request.body?.pitch, -500, 500, 0, '音调');
    const pitch = voice.supportsPitch ? requestedPitch : 0;
    const timed = request.body?.timed === true;
    const binaryTimedTransport = timed && request.body?.transport === 'binary-v1';
    const chargedChars = chargedTtsCharacters(text, voice.tier);
    const inputHash = sha256(
      JSON.stringify({ voiceId, text, speed, pitch, volume, timed })
    );

    await inTransaction(async (client) => {
      await ensureAccountNotRestricted(client, userId);
      await ensureTtsTrial(client, userId);
    });

    let reservation;
    try {
      reservation = await reserveTtsUsage(
        userId,
        requestId,
        voice.id,
        voice.tier,
        rawChars,
        chargedChars,
        inputHash
      );
    } catch (error) {
      if (error instanceof TtsQuotaError) {
        const statusCode = error.code === 'TTS_RATE_LIMITED'
          ? 429
          : error.code === 'TTS_DAILY_BUDGET_EXHAUSTED' ? 503 : 409;
        throw new ApiError(statusCode, error.code, error.message);
      }
      throw error;
    }

    if (reservation.usage.inputHash !== inputHash) {
      throw new ApiError(409, 'TTS_REQUEST_ID_REUSED', '请求标识已用于其他朗读内容');
    }
    if (reservation.duplicate) {
      const cached = reservation.usage.status === 'SUCCEEDED'
        ? readTtsAudioCache(`${userId}:${requestId}`)
        : null;
      const replayDecision = decideTtsReplay(reservation.usage.status, cached !== null);
      if (replayDecision === 'IN_PROGRESS') {
        throw new ApiError(409, 'TTS_REQUEST_IN_PROGRESS', '该段语音正在生成');
      }
      if (replayDecision === 'REFUNDED') {
        throw new ApiError(409, 'TTS_REQUEST_REFUNDED', '上次合成失败且字数已退回，请重新请求');
      }
      if (replayDecision === 'RETURN_CACHE' && cached) {
        return cached.kind === 'TIMED'
          ? sendTimedTtsAudio(
              reply,
              cached.result,
              reservation.usage.rawChars,
              reservation.usage.chargedChars,
              binaryTimedTransport
            )
          : sendTtsAudio(
              reply,
              cached.audio,
              reservation.usage.rawChars,
              reservation.usage.chargedChars
             );
      }
      throw new ApiError(
        409,
        'TTS_RESULT_EXPIRED',
        '该请求的语音缓存已过期，请使用新的请求标识重新生成'
      );
    }

    let releaseTtsSlot: (() => void) | null = null;
    try {
      releaseTtsSlot = await ttsConcurrency.acquire(userId);
    } catch (error) {
      if (!reservation.duplicate) {
        await refundTtsUsage(reservation.usage.id, 'TTS_SERVER_BUSY');
      }
      if (error instanceof TtsServerBusyError) {
        throw new ApiError(503, 'TTS_SERVER_BUSY', error.message);
      }
      throw error;
    }

    try {
      if (timed) {
        const result = await synthesizeTimedWithHuaweiSis({
          text,
          property: voice.property,
          speed,
          pitch,
          volume,
          wordTimestamps: voice.supportsWordTimestamps
        });
        const audioHash = sha256(result.audio);
        if (!reservation.duplicate) {
          await markTtsUsageSucceeded(reservation.usage.id, result.traceId, audioHash);
        }
        writeTtsAudioCache(`${userId}:${requestId}`, { kind: 'TIMED', result });
        return sendTimedTtsAudio(
          reply,
          result,
          rawChars,
          chargedChars,
          binaryTimedTransport
        );
      }
      const result = await synthesizeWithHuaweiSis({
        text,
        property: voice.property,
        speed,
        pitch,
        volume
      });
      const audioHash = sha256(result.audio);
      if (!reservation.duplicate) {
        await markTtsUsageSucceeded(reservation.usage.id, result.traceId, audioHash);
      }
      writeTtsAudioCache(`${userId}:${requestId}`, { kind: 'AUDIO', audio: result.audio });
      return sendTtsAudio(reply, result.audio, rawChars, chargedChars);
    } catch (error) {
      const code = error instanceof HuaweiSisError ? error.code : 'SIS_SYNTHESIS_FAILED';
      request.log.warn({
        err: error,
        userId,
        requestId,
        voiceId: voice.id,
        voiceProperty: voice.property,
        timed
      }, 'Huawei SIS synthesis failed');
      if (!reservation.duplicate) {
        await refundTtsUsage(reservation.usage.id, code);
      }
      throw new ApiError(502, code, '在线语音合成失败，请稍后重试');
    } finally {
      releaseTtsSlot();
    }
  }
);

app.post<{ Body: IapBody }>(
  '/v1/iap/credit',
  { preHandler: authenticate },
  async (request) => {
    const userId = requiredUserId(request);
    await enforceAccountRateLimit(
      userId,
      'iap-credit',
      Math.min(10, config.http.sensitiveRateLimitPerMinute)
    );
    const purchaseData = request.body?.purchaseData;
    if (!purchaseData) {
      throw new ApiError(400, 'INVALID_PURCHASE_DATA', '缺少华为订单数据');
    }
    let purchase;
    try {
      purchase = await verifyPurchaseData(purchaseData);
    } catch (error) {
      request.log.warn({ err: error, userId }, 'Huawei IAP verification failed');
      throw new ApiError(400, 'IAP_VERIFICATION_FAILED', '订单校验失败');
    }
    const orderId = purchase.purchaseOrderId!;
    const purchaseToken = purchase.purchaseToken!;
    const productId = purchase.productId!;
    const points = pointsForProduct(productId);
    const productType = Number(purchase.productType);

    const result = await inTransaction(async (client) => {
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`iap:${orderId}`]);
      const existing = await client.query<{
        user_id: string;
        credited_points: string;
        debt_offset_points: string;
      }>(
        `SELECT user_id, credited_points, debt_offset_points
         FROM iap_orders
         WHERE purchase_order_id = $1
         FOR UPDATE`,
        [orderId]
      );
      if (existing.rowCount) {
        if (existing.rows[0]!.user_id !== userId) {
          throw new ApiError(409, 'ORDER_ALREADY_CLAIMED', '该订单已绑定其他账号');
        }
        return {
          account: await snapshot(client, userId),
          creditedPoints: Number(existing.rows[0]!.credited_points)
            - Number(existing.rows[0]!.debt_offset_points),
          debtOffsetPoints: Number(existing.rows[0]!.debt_offset_points)
        };
      }

      const wallet = await client.query<{ balance: string; paid_balance: string }>(
        `SELECT balance, paid_balance
         FROM point_wallets
         WHERE user_id = $1
         FOR UPDATE`,
        [userId]
      );
      if (!wallet.rowCount) {
        throw new ApiError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
      }
      const debt = await client.query<{ iap_debt_points: string }>(
        `SELECT iap_debt_points FROM account_debts WHERE user_id = $1 FOR UPDATE`,
        [userId]
      );
      const debtBefore = Number(debt.rows[0]?.iap_debt_points || 0);
      const debtOffsetPoints = Math.min(debtBefore, points);
      const availablePoints = points - debtOffsetPoints;
      const creditedBalanceAfter = Number(wallet.rows[0]!.balance) + availablePoints;
      await client.query(
        `INSERT INTO iap_orders (
           purchase_order_id, purchase_token, user_id, product_id,
           credited_points, verified_payload, order_status, last_checked_at,
           debt_offset_points
         ) VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, now(), $8)`,
        [
          orderId,
          purchaseToken,
          userId,
          productId,
          points,
          JSON.stringify(purchase),
          purchaseState(purchase),
          debtOffsetPoints
        ]
      );
      await client.query(
        `UPDATE point_wallets
         SET balance = $2,
             paid_balance = $3,
             updated_at = now()
         WHERE user_id = $1`,
        [
          userId,
          creditedBalanceAfter,
          Number(wallet.rows[0]!.paid_balance) + availablePoints
        ]
      );
      if (debtOffsetPoints > 0) {
        await client.query(
          `UPDATE account_debts
           SET iap_debt_points = iap_debt_points - $2, updated_at = now()
           WHERE user_id = $1`,
          [userId, debtOffsetPoints]
        );
      }
      await client.query(
        `INSERT INTO point_ledger (
           user_id, delta, balance_after, reason, reference_id, idempotency_key
         ) VALUES ($1, $2, $3, 'IAP_RECHARGE', $4, $5)`,
        [userId, availablePoints, creditedBalanceAfter, orderId, `iap:${orderId}`]
      );
      return {
        account: await snapshot(client, userId),
        creditedPoints: availablePoints,
        debtOffsetPoints
      };
    });

    return {
      ...result,
      purchaseOrderId: orderId,
      // The client needs the verified token to acknowledge this consumable order to Huawei.
      purchaseToken,
      productType: Number.isFinite(productType) ? productType : 0
    };
  }
);

async function authenticate(request: AuthenticatedRequest, _reply: FastifyReply): Promise<void> {
  const authorization = request.headers.authorization || '';
  if (!authorization.startsWith('Bearer ')) {
    throw new ApiError(401, 'UNAUTHORIZED', '请先登录');
  }
  let userId = '';
  let sessionId = '';
  try {
    const verified = await jwtVerify(authorization.substring(7), sessionKey, {
      issuer: SESSION_ISSUER,
      audience: SESSION_AUDIENCE,
      algorithms: ['HS256']
    });
    userId = verified.payload.sub || '';
    sessionId = verified.payload.jti || '';
    if (!userId || !sessionId) throw new Error('Invalid session identity');
  } catch {
    throw new ApiError(401, 'SESSION_EXPIRED', '登录已过期，请重新登录');
  }
  const session = await pool.query(
    `SELECT 1 FROM auth_sessions
     WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL AND expires_at > now()`,
    [sessionId, userId]
  );
  if (!session.rowCount) {
    throw new ApiError(401, 'SESSION_EXPIRED', '登录已过期，请重新登录');
  }
  await enforceAccountRateLimit(
    userId,
    'authenticated-api',
    config.http.globalRateLimitPerMinute
  );
  request.userId = userId;
  request.sessionId = sessionId;
}

function requiredUserId(request: AuthenticatedRequest): string {
  if (!request.userId) {
    throw new ApiError(401, 'UNAUTHORIZED', '请先登录');
  }
  return request.userId;
}

async function issueSession(userId: string, sourceIp: string): Promise<string> {
  const sessionId = randomUUID();
  const expiresAt = sessionExpiresAt(config.auth.sessionTtlDays);
  await pool.query(
    `INSERT INTO auth_sessions (id, user_id, expires_at, created_ip)
     VALUES ($1, $2, $3, $4)`,
    [sessionId, userId, expiresAt, sourceIp]
  );
  return signSessionToken(sessionKey, userId, sessionId, expiresAt);
}

interface Queryable {
  query: PoolClient['query'];
}

async function activeTtsBalance(db: Queryable, userId: string, tier: TtsTier): Promise<number> {
  const result = await db.query<{ balance: string }>(
    `SELECT COALESCE(SUM(remaining_chars), 0)::bigint AS balance
     FROM tts_quota_grants
     WHERE user_id = $1
       AND tier = $2
       AND remaining_chars > 0
       AND expires_at > now()`,
    [userId, tier]
  );
  return Number(result.rows[0]?.balance || 0);
}

async function ensureAccountNotRestricted(db: Queryable, userId: string): Promise<void> {
  const debt = await db.query<{ iap_debt_points: string }>(
    'SELECT iap_debt_points FROM account_debts WHERE user_id = $1',
    [userId]
  );
  if (Number(debt.rows[0]?.iap_debt_points || 0) > 0) {
    throw new ApiError(403, 'ACCOUNT_PAYMENT_RESTRICTED', '账号存在退款欠款，暂时无法兑换或使用付费服务');
  }
}

async function ensureTtsTrial(client: PoolClient, userId: string): Promise<void> {
  const lockKey = `tts-trial:${userId}:v${TTS_TRIAL_VERSION}`;
  await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [lockKey]);
  await ensureTtsTrialTier(client, userId, 'STANDARD', TTS_STANDARD_TRIAL_CHARS);
  await ensureTtsTrialTier(client, userId, 'PREMIUM', TTS_PREMIUM_TRIAL_CHARS);
}

async function ensureTtsTrialTier(
  client: PoolClient,
  userId: string,
  tier: TtsTier,
  chars: number
): Promise<void> {
  await client.query(
    'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
    [`tts-quota:${userId}:${tier}`]
  );
  const idempotencyKey = `tts-trial:${userId}:v${TTS_TRIAL_VERSION}:${tier.toLowerCase()}`;
  const existing = await client.query(
    'SELECT 1 FROM tts_quota_ledger WHERE idempotency_key = $1',
    [idempotencyKey]
  );
  if (existing.rowCount) return;

  const balanceBefore = await activeTtsBalance(client, userId, tier);
  const grant = await client.query<{ id: string }>(
    `INSERT INTO tts_quota_grants (
       user_id, tier, source, total_chars, remaining_chars, expires_at, reference_id
     ) VALUES (
       $1, $2, 'TRIAL', $3, $3,
       now() + make_interval(days => $4), $5
     )
     RETURNING id`,
    [userId, tier, chars, TTS_TRIAL_VALID_DAYS, `trial-v${TTS_TRIAL_VERSION}`]
  );
  await client.query(
    `INSERT INTO tts_quota_ledger (
       user_id, grant_id, tier, delta_chars, balance_after,
       reason, reference_id, idempotency_key
     ) VALUES ($1, $2, $3, $4, $5, 'TRIAL_GRANT', $6, $7)`,
    [
      userId,
      grant.rows[0]!.id,
      tier,
      chars,
      balanceBefore + chars,
      `trial-v${TTS_TRIAL_VERSION}`,
      idempotencyKey
    ]
  );
}

async function ttsWallet(db: Queryable, userId: string) {
  const result = await db.query<{
    tier: TtsTier;
    balance: string;
    next_expiry_ms: string | null;
  }>(
    `SELECT
       tier,
       COALESCE(SUM(remaining_chars), 0)::bigint AS balance,
       (extract(epoch FROM MIN(expires_at)) * 1000)::bigint AS next_expiry_ms
     FROM tts_quota_grants
     WHERE user_id = $1
       AND remaining_chars > 0
       AND expires_at > now()
     GROUP BY tier`,
    [userId]
  );
  const byTier = new Map(result.rows.map((row) => [row.tier, row]));
  const standard = byTier.get('STANDARD');
  const premium = byTier.get('PREMIUM');
  return {
    standardChars: Number(standard?.balance || 0),
    premiumChars: Number(premium?.balance || 0),
    standardNextExpiry: standard?.next_expiry_ms ? Number(standard.next_expiry_ms) : null,
    premiumNextExpiry: premium?.next_expiry_ms ? Number(premium.next_expiry_ms) : null
  };
}

async function snapshot(db: Queryable, userId: string) {
  const account = await db.query<{
    id: string;
    display_name: string;
    avatar_url: string;
    has_custom_avatar: boolean;
    updated_at_ms: string;
    balance: string;
    paid_balance: string;
    promo_balance: string;
    welcome_granted: boolean;
    iap_debt_points: string;
  }>(
    `SELECT
       u.id,
       u.display_name,
       u.avatar_url,
       u.avatar_data IS NOT NULL AS has_custom_avatar,
       (extract(epoch FROM u.updated_at) * 1000)::bigint AS updated_at_ms,
       w.balance,
       w.paid_balance,
       w.promo_balance,
       COALESCE(d.iap_debt_points, 0)::bigint AS iap_debt_points,
       EXISTS (
         SELECT 1 FROM point_ledger l
         WHERE l.user_id = u.id AND l.reason = 'WELCOME_GRANT'
       ) AS welcome_granted
     FROM app_users u
     JOIN point_wallets w ON w.user_id = u.id
     LEFT JOIN account_debts d ON d.user_id = u.id
     WHERE u.id = $1`,
    [userId]
  );
  if (!account.rowCount) {
    throw new ApiError(404, 'ACCOUNT_NOT_FOUND', '账号不存在');
  }
  const entitlements = await db.query<{ theme_id: string; expires_at_ms: string }>(
    `SELECT theme_id, (extract(epoch FROM expires_at) * 1000)::bigint AS expires_at_ms
     FROM theme_entitlements
     WHERE user_id = $1
     ORDER BY theme_id`,
    [userId]
  );
  const row = account.rows[0]!;
  return {
    userId: row.id,
    displayName: row.display_name,
    avatarUrl: row.has_custom_avatar
      ? `${config.publicBaseUrl}/v1/avatars/${row.id}?v=${row.updated_at_ms}`
      : row.avatar_url,
    points: Number(row.balance),
    paidPoints: Number(row.paid_balance),
    promoPoints: Number(row.promo_balance),
    welcomeGranted: row.welcome_granted,
    iapDebtPoints: Number(row.iap_debt_points),
    entitlements: entitlements.rows.map((item) => ({
      themeId: item.theme_id,
      expiresAt: Number(item.expires_at_ms)
    }))
  };
}

function integerInRange(
  value: number | undefined,
  min: number,
  max: number,
  fallback: number,
  label: string
): number {
  if (value === undefined) return fallback;
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ApiError(400, 'INVALID_TTS_CONFIG', `${label}参数无效`);
  }
  return value;
}

function sha256(value: string | Buffer): string {
  return createHash('sha256').update(value).digest('hex');
}

function readTtsAudioCache(key: string): TtsCachedResponse | null {
  return ttsAudioCache.get(key);
}

function writeTtsAudioCache(key: string, response: TtsCachedResponse): void {
  const audioBytes = response.kind === 'TIMED'
    ? response.result.audio.length
    : response.audio.length;
  const metadataBytes = response.kind === 'TIMED'
    ? Buffer.byteLength(JSON.stringify(response.result.timings), 'utf8') + 256
    : 128;
  ttsAudioCache.set(key, response, audioBytes + metadataBytes);
}

function sendTtsAudio(
  reply: FastifyReply,
  audio: Buffer,
  rawChars: number,
  chargedChars: number
) {
  reply.header('Content-Type', 'audio/mpeg');
  reply.header('Content-Length', audio.length);
  reply.header('X-TTS-Raw-Chars', rawChars);
  reply.header('X-TTS-Charged-Chars', chargedChars);
  return reply.send(audio);
}

function sendTimedTtsAudio(
  reply: FastifyReply,
  result: SisTimedSynthesizeResult,
  rawChars: number,
  chargedChars: number,
  binaryTransport: boolean
) {
  reply.header('X-TTS-Raw-Chars', rawChars);
  reply.header('X-TTS-Charged-Chars', chargedChars);
  if (binaryTransport) {
    const payload = encodeTimedTtsBinary(
      result.audio,
      result.sampleRate,
      result.timingMode,
      result.timings
    );
    reply.header('Content-Type', TIMED_TTS_BINARY_CONTENT_TYPE);
    reply.header('Content-Length', payload.length);
    return reply.send(payload);
  }
  reply.header('Content-Type', 'application/json;charset=UTF-8');
  return reply.send({
    version: 1,
    audioBase64: result.audio.toString('base64'),
    sampleRate: result.sampleRate,
    timingMode: result.timingMode,
    timings: result.timings
  });
}

function acceptsGzip(request: FastifyRequest): boolean {
  const value = request.headers['accept-encoding'];
  return typeof value === 'string' && /(?:^|,|\s)gzip(?:,|\s|;|$)/i.test(value);
}

function gzipPayload(source: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    gzipCallback(source, { level: zlibConstants.Z_BEST_SPEED }, (error, result) => {
      if (error) {
        reject(error);
      } else {
        resolve(result);
      }
    });
  });
}

await pool.query('SELECT 1');
void refundStaleTtsReservations()
  .then((count) => {
    if (count > 0) app.log.warn({ count }, 'refunded stale TTS reservations');
  })
  .catch((error) => app.log.error(error, 'failed to refund stale TTS reservations'));
const ttsReservationTimer = setInterval(() => {
  void refundStaleTtsReservations()
    .then((count) => {
      if (count > 0) app.log.warn({ count }, 'refunded stale TTS reservations');
    })
    .catch((error) => app.log.error(error, 'failed to refund stale TTS reservations'));
}, 60_000);
ttsReservationTimer.unref();
const runSyncMaintenance = async () => {
  try {
    const [deletedReceipts, deletedTtsUsage] = await Promise.all([
      cleanupExpiredSyncReceipts(config.sync.receiptRetentionDays),
      cleanupExpiredTtsUsage(config.sis.usageRetentionDays)
    ]);
    if (deletedReceipts > 0 || deletedTtsUsage > 0) {
      app.log.info(
        { deletedReceipts, deletedTtsUsage },
        'deleted expired non-essential history'
      );
    }
  } catch (error) {
    app.log.error(error, 'failed to clean expired non-essential history');
  }
};
void runSyncMaintenance();
const syncMaintenanceTimer = setInterval(
  () => void runSyncMaintenance(),
  config.sync.maintenanceIntervalMs
);
syncMaintenanceTimer.unref();
const runSecurityMaintenance = async () => {
  try {
    await cleanupExpiredSecurityRows();
  } catch (error) {
    app.log.error(error, 'failed to clean expired security rows');
  }
};
void runSecurityMaintenance();
const securityMaintenanceTimer = setInterval(
  () => void runSecurityMaintenance(),
  6 * 60 * 60 * 1000
);
securityMaintenanceTimer.unref();
const runIapReconciliation = async () => {
  try {
    const result = await reconcileIapOrders();
    if (result.reversed > 0) {
      app.log.warn(result, 'reversed refunded or revoked IAP orders');
    }
  } catch (error) {
    app.log.error(error, 'failed to reconcile IAP orders');
  }
};
void runIapReconciliation();
const iapReconciliationTimer = setInterval(
  () => void runIapReconciliation(),
  config.iap.reconciliationIntervalMs
);
iapReconciliationTimer.unref();
await app.listen({ port: config.port, host: config.host });
