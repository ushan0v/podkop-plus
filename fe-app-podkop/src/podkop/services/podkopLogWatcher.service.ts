import { logger } from './logger.service';

export type LogFetcher = () => Promise<string> | string;

export interface PodkopLogWatcherOptions {
  intervalMs?: number;
  onNewLog?: (line: string) => void;
  suppressInitialLogs?: boolean;
  maxTrackedLines?: number;
}

export class PodkopLogWatcher {
  private static instance: PodkopLogWatcher;
  private fetcher?: LogFetcher;
  private onNewLog?: (line: string) => void;
  private intervalMs = 5000;
  private lastLines: string[] = [];
  private suppressInitialLogs = false;
  private initialized = false;
  private maxTrackedLines = 500;
  private timer?: ReturnType<typeof setInterval>;
  private running = false;
  private paused = false;
  private checking = false;

  private constructor() {
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', () => {
        if (document.hidden) this.pause();
        else this.resume();
      });
    }
  }

  static getInstance(): PodkopLogWatcher {
    if (!PodkopLogWatcher.instance) {
      PodkopLogWatcher.instance = new PodkopLogWatcher();
    }
    return PodkopLogWatcher.instance;
  }

  init(fetcher: LogFetcher, options?: PodkopLogWatcherOptions): void {
    this.fetcher = fetcher;
    this.onNewLog = options?.onNewLog;
    this.intervalMs = options?.intervalMs ?? 5000;
    this.suppressInitialLogs = options?.suppressInitialLogs ?? false;
    this.maxTrackedLines = options?.maxTrackedLines ?? 500;
    this.lastLines = [];
    this.initialized = false;
    logger.info(
      '[PodkopLogWatcher]',
      `initialized (interval: ${this.intervalMs}ms)`,
    );
  }

  private normalizeLines(raw: string): string[] {
    return raw.split('\n').filter(Boolean).slice(-this.maxTrackedLines);
  }

  private findOverlapLength(lines: string[]): number {
    const maxOverlap = Math.min(this.lastLines.length, lines.length);

    for (let length = maxOverlap; length > 0; length--) {
      let matches = true;
      const previousStart = this.lastLines.length - length;

      for (let index = 0; index < length; index++) {
        if (this.lastLines[previousStart + index] !== lines[index]) {
          matches = false;
          break;
        }
      }

      if (matches) {
        return length;
      }
    }

    return 0;
  }

  async checkOnce(): Promise<void> {
    if (!this.fetcher) {
      logger.warn('[PodkopLogWatcher]', 'fetcher not found');
      return;
    }

    if (this.paused) {
      logger.debug('[PodkopLogWatcher]', 'skipped check — tab not visible');
      return;
    }

    if (this.checking) {
      logger.debug(
        '[PodkopLogWatcher]',
        'skipped check — previous check is running',
      );
      return;
    }

    this.checking = true;

    try {
      const raw = await this.fetcher();
      const lines = this.normalizeLines(raw);

      if (!this.initialized) {
        this.initialized = true;
        this.lastLines = lines;

        if (this.suppressInitialLogs) {
          return;
        }

        for (const line of lines) {
          this.onNewLog?.(line);
        }

        return;
      }

      const overlapLength = this.findOverlapLength(lines);
      const newLines = this.lastLines.length
        ? lines.slice(overlapLength)
        : lines;

      for (const line of newLines) {
        this.onNewLog?.(line);
      }

      this.lastLines = lines;
    } catch (err) {
      logger.error('[PodkopLogWatcher]', 'failed to read logs:', err);
    } finally {
      this.checking = false;
    }
  }

  start(): void {
    if (this.running) return;
    if (!this.fetcher) {
      logger.warn('[PodkopLogWatcher]', 'attempted to start without fetcher');
      return;
    }

    this.running = true;
    void this.checkOnce();
    this.timer = setInterval(() => this.checkOnce(), this.intervalMs);
    logger.info(
      '[PodkopLogWatcher]',
      `started (interval: ${this.intervalMs}ms)`,
    );
  }

  stop(): void {
    if (!this.running) return;
    this.running = false;
    if (this.timer) clearInterval(this.timer);
    logger.info('[PodkopLogWatcher]', 'stopped');
  }

  pause(): void {
    if (!this.running || this.paused) return;
    this.paused = true;
    logger.info('[PodkopLogWatcher]', 'paused (tab not visible)');
  }

  resume(): void {
    if (!this.running || !this.paused) return;
    this.paused = false;
    logger.info('[PodkopLogWatcher]', 'resumed (tab active)');
    this.checkOnce(); // сразу проверить, не появились ли новые логи
  }

  reset(): void {
    this.lastLines = [];
    this.initialized = false;
    this.checking = false;
    logger.info('[PodkopLogWatcher]', 'log history reset');
  }
}
