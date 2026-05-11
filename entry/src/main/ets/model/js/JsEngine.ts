import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class LegadoCrypto {
  static base64Decode(input: string): string {
    try {
      const textDecoder = util.TextDecoder.create('utf-8');
      const helper = new util.Base64Helper();
      const uint8Arr = helper.decodeSync(input);
      return textDecoder.decodeWithStream(uint8Arr, { stream: false });
    } catch (e) {
      console.error('Base64解码失败:', e);
      return '';
    }
  }

  static base64Encode(input: string): string {
    try {
      const textEncoder = new util.TextEncoder();
      const uint8Arr = textEncoder.encodeInto(input);
      const helper = new util.Base64Helper();
      return helper.encodeToStringSync(uint8Arr);
    } catch (e) {
      console.error('Base64编码失败:', e);
      return '';
    }
  }

  static async desedeDecrypt(keyString: string, ivString: string, encryptedBase64: string): Promise<string> {
    try {
      const symKeyGenerator = cryptoFramework.createSymKeyGenerator('3DES192');
      const textEncoder = new util.TextEncoder();
      const keyBlob: cryptoFramework.DataBlob = {
        data: textEncoder.encodeInto(keyString)
      };
      const symKey = await symKeyGenerator.convertKey(keyBlob);

      const cipher = cryptoFramework.createCipher('3DES192|CBC|PKCS5');
      const ivBlob: cryptoFramework.DataBlob = {
        data: textEncoder.encodeInto(ivString)
      };
      const ivParams: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: ivBlob
      };
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivParams);

      const decoded = this.base64ToUint8Array(encryptedBase64);
      const dataBlob: cryptoFramework.DataBlob = { data: decoded };
      const result = await cipher.doFinal(dataBlob);

      const textDecoder = util.TextDecoder.create('utf-8');
      return textDecoder.decodeWithStream(result.data, { stream: false });
    } catch (e) {
      console.error('DESede解密失败:', e);
      return '';
    }
  }

  static base64ToUint8Array(base64: string): Uint8Array {
    try {
      const helper = new util.Base64Helper();
      return helper.decodeSync(base64);
    } catch (e) {
      return new Uint8Array(0);
    }
  }

  static simpleDecode(input: string): string {
    try {
      return input;
    } catch (e) {
      return input;
    }
  }
}

export interface JsExecuteContext {
  result: string;
  key?: string;
  page?: number;
  baseUrl?: string;
}

export class JsEngine {
  private context: JsExecuteContext;

  constructor(context: JsExecuteContext) {
    this.context = context;
  }

  async exec(jsCode: string): Promise<string> {
    try {
      // 检查 DESede 解密模式
      const keyMatch = jsCode.match(/SecretKeySpec\s*\(\s*String\s*\(\s*"([^"]+)"\s*\)/);
      const ivMatch = jsCode.match(/IvParameterSpec\s*\(\s*String\s*\(\s*"([^"]+)"\s*\)/);

      if (keyMatch && ivMatch) {
        const cleanInput = this.context.result.replace(/\{\{/g, '').replace(/\}\}/g, '');
        return await LegadoCrypto.desedeDecrypt(keyMatch[1], ivMatch[1], cleanInput);
      }

      return this.context.result;
    } catch (e) {
      console.error('JS执行失败:', e);
      return this.context.result;
    }
  }
}