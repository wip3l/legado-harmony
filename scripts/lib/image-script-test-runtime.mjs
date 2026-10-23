import vm from 'node:vm';
import crypto from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './ets-module-staging.mjs';

// Node adapter for testing the actual runner/prelude. Native NAPI/QuickJS semantics
// are covered separately by ScriptThreadProbe on a HarmonyOS device.
export function imageScriptTestRuntime() {
  const stats = { created: 0, released: 0, active: 0, maxActive: 0, delay: 0, helpers: 0 };
  function cryptoOperation(name, bytes, options) {
    const { algorithm, keyHex, ivHex } = JSON.parse(options);
    if (name === 'hash') return crypto.createHash(algorithm).update(bytes).digest();
    if (name === 'hmac') return crypto.createHmac(algorithm, Buffer.from(keyHex, 'hex')).update(bytes).digest();
    const [family, mode, padding] = algorithm.toLowerCase().split('/');
    const key = Buffer.from(keyHex, 'hex');
    const cipherName = family === 'aes' ? `aes-${key.length * 8}-${mode}` : `des-ede3-${mode}`;
    const cipher = (name === 'encrypt' ? crypto.createCipheriv : crypto.createDecipheriv)(cipherName, key,
      mode === 'ecb' ? null : Buffer.from(ivHex, 'hex'));
    cipher.setAutoPadding(padding !== 'nopadding');
    return Buffer.concat([cipher.update(bytes), cipher.final()]);
  }
  class Session {
    constructor(host, options, binaryHost) {
      stats.created++; stats.active++; stats.maxActive = Math.max(stats.maxActive, stats.active);
      this.host = binaryHost;
    }
    async evaluateBinary(code, input) {
      if (stats.delay) await new Promise(resolve => setTimeout(resolve, stats.delay));
      if (this.cancelled) return { success: false, cancelled: true, error: 'cancelled' };
      let calls = 0, size = 0;
      const context = vm.createContext({
        Uint8Array, Uint16Array, Int8Array, ArrayBuffer,
        __imageInput: new Uint8Array(input).buffer,
        __host() { throw new Error('image scripts cannot call the stage host'); },
        __imageHost(name, bytes, options) {
          stats.helpers++;
          if (++calls > 16 || (size += bytes.byteLength) > 80 * 1024 * 1024) throw new Error('budget exceeded');
          return new Uint8Array(cryptoOperation(name, bytes, options)).buffer;
        }
      });
      try {
        const output = await vm.runInContext(code, context, { timeout: 100 });
        if (!(output instanceof ArrayBuffer) && !(ArrayBuffer.isView(output) && output.BYTES_PER_ELEMENT === 1)) {
          throw new Error('image result must be an ArrayBuffer or an 8-bit typed array');
        }
        const bytes = output instanceof ArrayBuffer ? new Uint8Array(output) : new Uint8Array(output.buffer, output.byteOffset, output.byteLength);
        return { success: true, bytes: bytes.slice() };
      } catch (error) {
        return { success: false, error: error.message, timedOut: error.code === 'ERR_SCRIPT_EXECUTION_TIMEOUT' };
      }
    }
    cancel() { this.cancelled = true; }
    release() { stats.released++; stats.active--; }
  }
  const context = vm.createContext({ console, setTimeout, setInterval, clearInterval, Uint8Array, ArrayBuffer,
    JSScriptSession: Session, JSScriptSessionOptions: class {}, NativeSourceCrypto: { imageOperation: cryptoOperation },
    // 轻页不安装图片脚本执行器，走内核自带的会话；条带重排由内核仓库的 image-strip-check 覆盖。
    SourceEngineHost: { imageScripts: () => undefined },
    NativeImageTransform: { reorderStrips: () => { throw new Error('reorderStrips is not available in Node'); } } });
  const code = stripTypeScriptTypes(readEtsModule('core/nativesource/NativeImageScriptRunner.ts')
    .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' });
  vm.runInContext(code, context);
  return { runner: vm.runInContext('NativeImageScriptRunner', context), stats };
}
