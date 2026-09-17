export class BookSourceHostActionKind {
  static readonly HTTP_REQUEST: string = 'http-request';
  static readonly COOKIE_MUTATION: string = 'cookie-mutation';
  static readonly CRYPTO_REQUEST: string = 'crypto-request';
  static readonly VARIABLE_MUTATION: string = 'variable-mutation';
}

/**
 * Engine-neutral host-action journal. ArkWeb uses it now; QuickJS can use the same request/replay
 * contract later without receiving direct network, Cookie, database or filesystem access.
 */
export class BookSourceExecutionJournal {
  responses: Record<string, string> = {};
  // Response headers keyed by the same request spec as `responses`, JSON-encoded with
  // original header casing. The ArkWeb bridge replays them into responseObject.headers().
  responseHeaders: Record<string, string> = {};
  private startedRequestIds: string[] = [];
  private completedRequestIds: string[] = [];
  private appliedOperationIds: string[] = [];
  private appliedOperationPayloads: string[] = [];
  private sideEffectsStarted: boolean = false;

  reset(): void {
    this.responses = {};
    this.responseHeaders = {};
    this.startedRequestIds = [];
    this.completedRequestIds = [];
    this.appliedOperationIds = [];
    this.appliedOperationPayloads = [];
    this.sideEffectsStarted = false;
  }

  hasResponse(request: string): boolean {
    return Object.prototype.hasOwnProperty.call(this.responses, request || '');
  }

  response(request: string): string {
    return this.responses[request || ''] || '';
  }

  markRequestStarted(request: string): boolean {
    const id = this.stableId(`request\n${request || ''}`);
    if (this.startedRequestIds.includes(id)) return false;
    this.startedRequestIds.push(id);
    this.sideEffectsStarted = true;
    return true;
  }

  recordResponse(request: string, response: string): void {
    const key = request || '';
    this.responses[key] = response || '';
    const id = this.stableId(`request\n${key}`);
    if (!this.completedRequestIds.includes(id)) this.completedRequestIds.push(id);
  }

  /** Stores the fetched response's headers so the bridge can expose responseObject.headers(). */
  recordResponseHeaders(request: string, headers: Record<string, string>): void {
    const key = request || '';
    const record: Record<string, string> = {};
    for (const name of Object.keys(headers || {})) {
      const value = headers[name];
      if (name && value !== undefined && value !== null && typeof value !== 'object') {
        record[name] = String(value);
      }
    }
    this.responseHeaders[key] = JSON.stringify(record);
  }

  markOperationApplied(kind: string, payload: string): boolean {
    const operationKind = kind || 'operation';
    const operationPayload = payload || '';
    const record = `${operationKind}\n${operationPayload}`;
    const id = this.stableId(record);
    if (this.appliedOperationIds.includes(id)) return false;
    this.appliedOperationIds.push(id);
    this.appliedOperationPayloads.push(record);
    this.sideEffectsStarted = true;
    return true;
  }

  appliedOperations(kind: string): string[] {
    const prefix = `${kind || 'operation'}\n`;
    const result: string[] = [];
    for (const record of this.appliedOperationPayloads) {
      if (record.startsWith(prefix)) result.push(record.substring(prefix.length));
    }
    return result;
  }

  canFallback(): boolean {
    return !this.sideEffectsStarted;
  }

  private stableId(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index++) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return `${hash >>> 0}`;
  }
}
