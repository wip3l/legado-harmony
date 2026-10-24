import { common } from '@kit.AbilityKit';
import { ComicColorizer } from './ComicColorizer';
import { ReaderImageMarker } from '../book/ReaderImageMarker';
import { ReaderImageResults } from '../book/ReaderImageResults';

export class ComicColorCandidate {
  source: string;
  visible: boolean;
  distance: number;
  label: string;
  constructor(source: string, visible: boolean, distance: number, label: string = '') {
    this.source = source;
    this.visible = visible;
    this.distance = distance;
    this.label = label;
  }
}

/** One reader, one replaceable viewport queue. Native prediction is only cooperatively cancelled. */
export class ReaderComicColorSession {
  enabled: boolean = false;
  paused: boolean = false;
  comparing: boolean = false;
  foreground: boolean = false;
  status: string = '开启后优先着色当前画面';
  private context: common.Context | null = null;
  private book: string = '';
  private epoch: number = 0;
  private running: boolean = false;
  private busyLabel: string = '';
  private prioritySource: string = '';
  private candidates: ComicColorCandidate[] = [];
  private manual: Set<string> = new Set();
  private compared: Set<string> = new Set();
  private results: Map<string, string> = new Map();
  private errors: Map<string, string> = new Map();
  private listeners: Set<() => void> = new Set();
  private touching: boolean = false;
  private movingUntil: number = 0;
  private wasMoving: boolean = false;
  private allowed: boolean = false;
  private timer: number = -1;

  static source(marker: string): string {
    const value = ReaderImageMarker.parse(marker).source;
    const pending = ReaderImageMarker.pendingRaw(value);
    const source = pending ? ReaderImageResults.current(pending) : value;
    return ReaderImageMarker.failureReason(source) ? '' : source;
  }

  configure(context: common.Context, book: string, enabled: boolean): void {
    this.context = context;
    if (this.book !== book) {
      this.epoch++;
      this.book = book;
      this.results.clear();
      this.errors.clear();
      this.manual.clear();
      this.prioritySource = '';
      this.candidates = [];
      this.paused = false;
      this.clearCompare();
    }
    this.setEnabled(enabled);
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return (): void => { this.listeners.delete(listener); };
  }

  private emit(): void { this.listeners.forEach((listener: () => void): void => listener()); }

  setForeground(value: boolean): void {
    if (value === this.foreground) return;
    this.foreground = value;
    this.epoch++;
    this.touching = false;
    this.movingUntil = 0;
    if (this.timer !== -1) clearInterval(this.timer);
    this.timer = value ? setInterval((): void => this.tick(), 250) : -1;
    this.tick();
  }

  setEnabled(value: boolean): void {
    if (this.enabled !== value) this.epoch++;
    this.enabled = value;
    if (!value) { this.manual.clear(); this.clearCompare(); }
    this.paused = false;
    this.tick();
    this.emit();
  }

  active(): boolean { return this.enabled || this.manual.size > 0; }
  moving(): boolean { return this.touching || Date.now() < this.movingUntil; }
  touch(down: boolean): void {
    this.touching = down;
    this.motion();
  }
  motion(): void { this.movingUntil = Date.now() + 300; }

  update(candidates: ComicColorCandidate[]): void {
    this.candidates = candidates.filter((item: ComicColorCandidate): boolean => !!item.source)
      .sort((a: ComicColorCandidate, b: ComicColorCandidate): number =>
        Number(b.visible) - Number(a.visible) || a.distance - b.distance).slice(0, 32);
    this.tick();
  }

  visible(): ComicColorCandidate[] {
    return this.candidates.filter((item: ComicColorCandidate): boolean => item.visible);
  }

  single(source: string): void {
    this.prioritySource = source;
    this.manual.add(source);
    this.errors.delete(source);
    this.paused = false;
    this.tick();
    this.emit();
  }

  togglePause(): void {
    this.paused = !this.paused;
    this.epoch++;
    this.tick();
    this.emit();
  }

  toggleCompare(): void {
    if (this.comparing) this.clearCompare();
    else {
      this.comparing = true;
      this.visible().forEach((item: ComicColorCandidate): void => { this.compared.add(item.source); });
    }
    this.emit();
  }
  clearCompare(): void {
    const changed = this.comparing;
    this.comparing = false;
    this.compared.clear();
    if (changed) this.emit();
  }

  uri(source: string): string {
    if (!ComicColorizer.memberAllowed() || (!this.enabled && !this.manual.has(source)) ||
      this.compared.has(source)) return '';
    return this.results.get(source) || '';
  }
  exportUri(source: string): string {
    return ComicColorizer.memberAllowed() && this.active() ? this.results.get(source) || '' : '';
  }
  failed(source: string): void {
    this.results.delete(source);
    this.errors.set(source, '彩色缓存已失效，请重试当前画面');
    this.emit();
  }
  retry(): void {
    this.visible().forEach((item: ComicColorCandidate): void => { this.errors.delete(item.source); });
    this.paused = false;
    this.tick();
  }

  private tick(): void {
    const allowed = ComicColorizer.memberAllowed();
    if (allowed !== this.allowed) {
      this.allowed = allowed;
      this.epoch++;
      this.emit();
    }
    const moving = this.moving();
    if (this.wasMoving && !moving) this.emit();
    this.wasMoving = moving;
    let status = '开启后优先着色当前画面';
    if (this.active()) {
      const failed = this.visible().find((item: ComicColorCandidate): boolean => this.errors.has(item.source));
      status = !ComicColorizer.supported() ? '当前设备不支持本地着色' : !allowed ? '会员已到期，续费后恢复彩色阅读' :
        !this.foreground ? '已停止后台着色' : this.paused ? '已暂停 · 保留已完成的彩色画面' :
          failed ? this.errors.get(failed.source) || '当前画面未完成，请重试' :
            this.running ? `正在着色第 ${this.busyLabel || '?'} 张 · 可继续阅读` : '彩色阅读已开启';
    }
    if (status !== this.status) { this.status = status; this.emit(); }
    if (!this.context || !this.foreground || !allowed || !ComicColorizer.supported() ||
      this.paused || this.running || !this.active() || moving) return;
    const pending = this.candidates.filter((item: ComicColorCandidate): boolean =>
      (this.enabled || this.manual.has(item.source)) && !this.results.has(item.source) && !this.errors.has(item.source));
    const next = pending.find((item: ComicColorCandidate): boolean => item.source === this.prioritySource) || pending[0];
    if (!next) return;
    const epoch = this.epoch;
    this.running = true;
    this.busyLabel = next.label;
    const active = (): boolean => epoch === this.epoch && this.foreground && !this.paused &&
      (this.enabled || this.manual.has(next.source)) && this.candidates.some(
        (item: ComicColorCandidate): boolean => item.source === next.source);
    ComicColorizer.colorize(this.context, next.source, active, (_status: string): void => {}).then((result): void => {
      if (!active()) return;
      this.results.set(next.source, result.uri);
      // URI metadata only; decoded bitmaps remain owned by visible Image components.
      if (this.results.size > 96) {
        const old = Array.from(this.results.keys()).find((source: string): boolean =>
          !this.candidates.some((item: ComicColorCandidate): boolean => item.source === source));
        if (old) this.results.delete(old);
      }
    }).catch((error: Error): void => {
      if (active() && error.message !== ComicColorizer.CANCELLED && error.message !== ComicColorizer.MEMBER_REQUIRED) {
        this.errors.set(next.source, error.message || '着色失败，请重试当前画面');
        if (this.errors.size > 96) {
          const old = Array.from(this.errors.keys()).find((source: string): boolean =>
            !this.candidates.some((item: ComicColorCandidate): boolean => item.source === source));
          if (old) this.errors.delete(old);
        }
      }
    }).finally((): void => {
      this.running = false;
      this.emit();
      this.tick();
    });
  }
}
