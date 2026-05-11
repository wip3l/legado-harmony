export class RuleContext {
  private vars: Record<string, string> = {};

  put(key: string, value: string): void {
    this.vars[key] = value;
  }

  get(key: string): string {
    return this.vars[key] || '';
  }

  has(key: string): boolean {
    return key in this.vars;
  }

  loadFromJson(json: string): void {
    try {
      const obj = JSON.parse(json) as Record<string, string>;
      Object.assign(this.vars, obj);
    } catch (_) {}
  }

  toJson(): string {
    return JSON.stringify(this.vars);
  }

  toRecord(): Record<string, string> {
    return { ...this.vars };
  }
}