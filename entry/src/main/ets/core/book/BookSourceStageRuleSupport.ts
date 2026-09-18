import { BookSource } from '../../model/data/Book';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { BookSourceRuntimeRouter, SourceRuntimeStage } from './BookSourceRuntimeRouter';
import { BookSourceStageWebRuntime, StageWebRuntimeRequest } from './BookSourceStageWebRuntime';
import { RuleExecutionTarget, RuleValue } from '../rule/RuleValue';

class EmbeddedStageRule {
  baseRule: string = '';
  code: string = '';
  trailingRule: string = '';
}

/** Full-JavaScript post-processing for list rules such as `jsonPath <js>...</js>`. */
export class BookSourceStageRuleSupport {
  static async getElements(source: BookSource, content: string, baseUrl: string,
    rawRule: string, stage: string = SourceRuntimeStage.SEARCH, ownerId: string = '',
    maxResponseBytes: number = 8 * 1024 * 1024,
    maxTotalResponseBytes: number = 16 * 1024 * 1024,
    variables: Record<string, string> = {}): Promise<string[] | null> {
    const embedded = this.splitEmbeddedRule(rawRule || '');
    if (!embedded || !embedded.code || (!embedded.baseRule && !embedded.trailingRule)) return null;
    const decision = BookSourceRuntimeRouter.decide(stage, `${source.jsLib || ''}\n${embedded.code}`);
    const runtime = BookSourceStageWebRuntime.get();
    if (decision.runtime !== 'arkweb') return null;
    if (!runtime.isAvailable() && !await runtime.waitUntilAvailable(8000)) return null;

    if (embedded.trailingRule) {
      const request = new StageWebRuntimeRequest();
      request.applyStageBudget(stage);
      request.source = source;
      request.content = content || '';
      request.contextContent = content || '';
      request.baseUrl = baseUrl || source.bookSourceUrl;
      request.variables = variables;
      request.code = embedded.code;
      request.ownerId = ownerId;
      request.maxResponseBytes = Math.min(request.maxResponseBytes, maxResponseBytes);
      request.maxTotalResponseBytes = Math.min(request.maxTotalResponseBytes, maxTotalResponseBytes);
      try {
        const result = await runtime.execute(request);
        const transformed = (result.value || '').trim();
        if (!transformed) return [];
        let trailingRule = embedded.trailingRule.trim();
        const reverse = trailingRule.startsWith('-') && trailingRule.length > 1;
        if (reverse) trailingRule = trailingRule.substring(1).trim();
        const values = new AnalyzeRule(transformed, baseUrl).analyze(trailingRule);
        return reverse ? values.reverse() : values;
      } catch (error) {
        console.warn('[StageRule] list pre-process failed, fallback legacy:', source.bookSourceName, error);
        return null;
      }
    }

    const baseItemValues = new AnalyzeRule(content || '', baseUrl)
      .execute(embedded.baseRule, RuleExecutionTarget.ELEMENTS);
    const baseItems = baseItemValues.map((item: RuleValue): string => item.asString());
    const values: Object[] = [];
    for (const item of baseItemValues) values.push(item.runtimeValue());
    const request = new StageWebRuntimeRequest();
    request.applyStageBudget(stage);
    request.source = source;
    request.content = JSON.stringify(values);
    request.contextContent = content || '';
    request.baseUrl = baseUrl || source.bookSourceUrl;
    request.variables = variables;
    request.code = embedded.code;
    request.ownerId = ownerId;
    request.maxResponseBytes = Math.min(request.maxResponseBytes, maxResponseBytes);
    request.maxTotalResponseBytes = Math.min(request.maxTotalResponseBytes, maxTotalResponseBytes);
    try {
      const result = await runtime.execute(request);
      const parsed = JSON.parse(result.value || '[]') as Object;
      if (!Array.isArray(parsed)) return null;
      // A stage runtime may complete without throwing while still losing the evaluated expression
      // (for example when a source library exports top-level helpers through `this`). Let the legacy
      // analyzer execute the same embedded script before accepting an unexpected empty list.
      if (parsed.length === 0 && baseItems.length > 0) return null;
      return parsed.map((item: Object): string => typeof item === 'string' ? item : JSON.stringify(item));
    } catch (error) {
      console.warn('[StageRule] list post-process failed, fallback legacy:', source.bookSourceName, error);
      return null;
    }
  }

  private static splitEmbeddedRule(rawRule: string): EmbeddedStageRule | null {
    const raw = (rawRule || '').trim();
    const leadingBlock = raw.match(/^<js>([\s\S]*?)<\/js>\s*([\s\S]+)$/i);
    if (leadingBlock && leadingBlock[1].trim() && leadingBlock[2].trim()) {
      const result = new EmbeddedStageRule();
      result.code = leadingBlock[1].trim();
      result.trailingRule = leadingBlock[2].trim();
      return result;
    }
    const block = raw.match(/^([\s\S]*?)<js>([\s\S]*?)<\/js>\s*$/i);
    if (block && block[1].trim() && block[2].trim()) {
      const result = new EmbeddedStageRule();
      result.baseRule = block[1].trim();
      result.code = block[2].trim();
      return result;
    }
    const suffixIndex = raw.indexOf('@js:');
    if (suffixIndex > 0) {
      const result = new EmbeddedStageRule();
      result.baseRule = raw.substring(0, suffixIndex).trim();
      result.code = raw.substring(suffixIndex + 4).trim();
      return result.baseRule && result.code ? result : null;
    }
    return null;
  }
}
