import { JSBoundedExecutionResult, JSContext, JSRuntimeOptions } from '@devzeng/quickjs';
import { QuickJsObservationContext, QuickJsRuntimeMode, QuickJsRuntimeStatus } from './QuickJsRuntimeStatus';
import { QuickJsValidationStore } from './QuickJsValidationStore';

export class QuickJsExpressionResult {
  success: boolean = false;
  value: string = '';
  error: string = '';
  timedOut: boolean = false;
  elapsedMs: number = 0;
}

/**
 * Sandboxed pure-expression runner used by the migration router.
 *
 * It deliberately exposes no network, Cookie, filesystem or platform bridge. Host actions remain
 * on the existing audited path and will later be represented by an explicit action journal.
 */
export class QuickJsScriptRuntime {
  private static readonly MAX_SCRIPT_LENGTH: number = 4096;
  private static readonly MAX_BINDING_COUNT: number = 64;
  private static readonly MAX_BINDING_BYTES: number = 128 * 1024;

  static isPureExpressionCandidate(expression: string): boolean {
    const code = QuickJsScriptRuntime.normalizeExpression(expression);
    if (!code || code.length > QuickJsScriptRuntime.MAX_SCRIPT_LENGTH) return false;
    // Legado replacement operators and @-paths are rule-language syntax, not JavaScript. A bare
    // `$` is valid here because structured RuleValue bindings are now represented explicitly.
    const syntax = QuickJsScriptRuntime.stripLiterals(code);
    if (syntax.includes('##') || /(^|[^A-Za-z0-9_$])@(?:\.|\[)/.test(syntax)) return false;
    if (/[;{}]/.test(code)) return false;
    if (/(^|[^=!<>])=(?!=|>)/.test(code)) return false;
    if (/\+\+|--/.test(code)) return false;
    if (/\b(?:var|let|const|function|class|while|for|do|switch|try|catch|throw|return|await|yield|import|export|delete|new)\b/.test(code)) return false;
    if (/\b(?:java|cookie|source|book|chapter|fetch|request|webView|WebView|Packages|android|crypto|eval|Function|globalThis|performance)\b/.test(code)) return false;
    if (/\bDate\b|Math\.random\s*\(/.test(code)) return false;
    if (QuickJsScriptRuntime.hasUnknownBareCall(code)) return false;
    return true;
  }

  static evaluateExpression(expression: string,
    variables: Record<string, Object>, timeoutMs: number = 80): QuickJsExpressionResult {
    const output = new QuickJsExpressionResult();
    const code = QuickJsScriptRuntime.normalizeExpression(expression);
    if (!QuickJsScriptRuntime.isPureExpressionCandidate(code)) {
      output.error = 'not-pure-expression';
      return output;
    }
    return QuickJsScriptRuntime.evaluateBoundExpression(code, variables, timeoutMs, output);
  }

  /**
   * Evaluate the residue a textual rule shim left behind (literal values plus plain JavaScript
   * operators/methods such as `String(x).replace(/…/,'')`). The strict pure-expression gate would
   * reject these on regex literals (`--`) or comparison operators, so screen only shapes the
   * sandbox cannot honor; unbindable host identifiers simply fail evaluation and the caller falls
   * back to its legacy behavior.
   */
  static evaluateResidualExpression(expression: string,
    variables: Record<string, Object>, timeoutMs: number = 150): QuickJsExpressionResult {
    const output = new QuickJsExpressionResult();
    const code = QuickJsScriptRuntime.normalizeExpression(expression);
    if (!code || code.length > QuickJsScriptRuntime.MAX_SCRIPT_LENGTH) {
      output.error = 'not-residual';
      return output;
    }
    if (/[;{}]/.test(code) ||
      /\b(?:java|cookie|cache|chapter)\s*\.\s*[A-Za-z_$]|\b(?:eval|Function|import|while|for|return|await|yield|throw|new)\b/.test(code)) {
      output.error = 'not-residual';
      return output;
    }
    return QuickJsScriptRuntime.evaluateBoundExpression(code, variables, timeoutMs, output);
  }

  private static evaluateBoundExpression(code: string, variables: Record<string, Object>,
    timeoutMs: number, output: QuickJsExpressionResult): QuickJsExpressionResult {
    const keys = Object.keys(variables);
    if (keys.length > QuickJsScriptRuntime.MAX_BINDING_COUNT) {
      output.error = 'too-many-bindings';
      return output;
    }
    let bindingBytes = 0;
    const declarations: string[] = [];
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      let serialized = '';
      try { serialized = JSON.stringify(variables[key]); } catch (_) { serialized = String(variables[key]); }
      bindingBytes += key.length + serialized.length;
      if (QuickJsScriptRuntime.isSafeIdentifier(key)) {
        declarations.push(`const ${key}=__bindings[${JSON.stringify(key)}]`);
      }
    }
    if (bindingBytes > QuickJsScriptRuntime.MAX_BINDING_BYTES) {
      output.error = 'bindings-too-large';
      return output;
    }

    return QuickJsScriptRuntime.evaluateInContext(code, variables, declarations, timeoutMs, output,
      'book-source-pure-expression.js');
  }

  private static evaluateInContext(code: string, variables: Record<string, Object>,
    declarations: string[], timeoutMs: number, output: QuickJsExpressionResult,
    scriptName: string): QuickJsExpressionResult {
    const options = new JSRuntimeOptions();
    options.memoryLimitBytes = 16 * 1024 * 1024;
    options.stackLimitBytes = 512 * 1024;
    const context = new JSContext(options);
    try {
      context.setObject(variables, '__legadoBindings');
      const wrapped = `(function(){const __bindings=globalThis.__legadoBindings;` +
        `${declarations.join(';')};return (${code});})()`;
      const result = context.evaluateBounded(wrapped, scriptName,
        Math.max(10, Math.min(250, timeoutMs)), 8);
      QuickJsScriptRuntime.copyResult(result, output);
    } catch (error) {
      output.error = QuickJsScriptRuntime.errorMessage(error);
    } finally {
      context.release();
    }
    return output;
  }

  private static normalizeExpression(expression: string): string {
    return (expression || '').trim().replace(/^return\s+/, '').replace(/;\s*$/, '').trim();
  }

  private static hasUnknownBareCall(code: string): boolean {
    const safeCalls = ['String', 'Number', 'Boolean', 'RegExp', 'parseInt', 'parseFloat', 'isNaN',
      'encodeURIComponent', 'encodeURI', 'decodeURIComponent', 'decodeURI'];
    // Remove literals before looking for calls so text and regular-expression groups do not look
    // like executable identifiers. Method calls are allowed; only unqualified host/jsLib calls
    // need to remain on the full runtime.
    const scan = QuickJsScriptRuntime.stripLiterals(code);
    const calls = /[A-Za-z_$][A-Za-z0-9_$]*\s*\(/g;
    let match: RegExpExecArray | null = null;
    while ((match = calls.exec(scan)) !== null) {
      const raw = match[0];
      const name = raw.substring(0, raw.indexOf('(')).trim();
      const previous = match.index > 0 ? scan.charAt(match.index - 1) : '';
      if (previous === '.' || safeCalls.includes(name)) continue;
      return true;
    }
    return false;
  }

  private static stripLiterals(code: string): string {
    return code
      .replace(/(['"`])(?:\\.|(?!\1)[\s\S])*?\1/g, ' ')
      .replace(/\/(?:\\.|[^/\\\r\n])+\/[dgimsuvy]*/g, ' ');
  }

  private static isSafeIdentifier(key: string): boolean {
    if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key)) return false;
    return !/^(?:break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|function|if|import|in|instanceof|let|new|return|super|switch|this|throw|try|typeof|var|void|while|with|yield|await|enum|implements|interface|package|private|protected|public|static)$/.test(key);
  }

  private static copyResult(source: JSBoundedExecutionResult, target: QuickJsExpressionResult): void {
    target.success = source.success;
    target.value = source.value;
    target.error = source.error;
    target.timedOut = source.timedOut;
    target.elapsedMs = source.elapsedMs;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message;
    return String(error);
  }
}

/** Bounded shadow comparison. The legacy value always remains authoritative in SHADOW mode. */
export class QuickJsShadowComparator {
  private static readonly MAX_SAMPLES: number = 64;
  private static samples: number = 0;
  private static samplesByFingerprint: Record<string, number> = {};

  static compare(expression: string, variables: Record<string, Object>, legacyValue: string,
    observation: QuickJsObservationContext | null = null): void {
    const validationTarget = QuickJsValidationStore.isValidationTarget(observation,
      QuickJsShadowComparator.fingerprint(expression));
    if (!QuickJsRuntimeStatus.isHealthy() ||
      QuickJsRuntimeStatus.getMode() !== QuickJsRuntimeMode.SHADOW ||
      (!validationTarget && QuickJsShadowComparator.samples >= QuickJsShadowComparator.MAX_SAMPLES) ||
      !QuickJsScriptRuntime.isPureExpressionCandidate(expression)) {
      return;
    }
    const submitter = QuickJsRuntimeStatus.getShadowSubmitter();
    if (!submitter) return;
    const fingerprint = QuickJsShadowComparator.fingerprint(expression);
    const sampleKey = observation ? `${observation.sourceUrl}\n${observation.stage}\n${observation.field}\n${fingerprint}` :
      fingerprint;
    const fingerprintSamples = QuickJsShadowComparator.samplesByFingerprint[sampleKey] || 0;
    // A targeted validation session needs four real observations to reach the canary gate.
    // Ordinary shadow mode remains capped at two observations per fingerprint.
    if (fingerprintSamples >= (validationTarget ? 4 : 2)) return;
    const sample = validationTarget ? fingerprintSamples + 1 : QuickJsShadowComparator.samples + 1;
    if (!submitter.submit(expression, JSON.stringify(variables), legacyValue, fingerprint, sample,
      observation)) return;
    QuickJsShadowComparator.samplesByFingerprint[sampleKey] = fingerprintSamples + 1;
    if (!validationTarget) QuickJsShadowComparator.samples = sample;
  }

  static resetSampling(): void {
    QuickJsShadowComparator.samples = 0;
    QuickJsShadowComparator.samplesByFingerprint = {};
  }

  static fingerprint(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index++) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
  }
}
