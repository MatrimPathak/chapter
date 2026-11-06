/**
 * In-memory token bucket. Used to keep each function instance within its
 * share of Hardcover's 60 requests/minute budget (docs/04 §1.2).
 */
export class TokenBucket {
  private tokens: number;
  private last: number;

  constructor(
    private readonly capacity: number,
    private readonly refillPerMs: number,
    private readonly now: () => number = Date.now,
  ) {
    this.tokens = capacity;
    this.last = now();
  }

  /** Requests per minute convenience constructor. */
  static perMinute(n: number, now?: () => number): TokenBucket {
    return new TokenBucket(n, n / 60_000, now);
  }

  tryTake(): boolean {
    const t = this.now();
    this.tokens = Math.min(
      this.capacity,
      this.tokens + (t - this.last) * this.refillPerMs,
    );
    this.last = t;
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}

/**
 * Skips a provider for [cooldownMs] after [threshold] consecutive failures
 * (docs/04 §1.2: 5 failures → 60 s).
 */
export class CircuitBreaker {
  private failures = 0;
  private openedAt: number | null = null;

  constructor(
    private readonly threshold = 5,
    private readonly cooldownMs = 60_000,
    private readonly now: () => number = Date.now,
  ) {}

  canAttempt(): boolean {
    if (this.openedAt === null) return true;
    if (this.now() - this.openedAt >= this.cooldownMs) {
      // Half-open: allow one trial; a failure re-opens immediately.
      this.openedAt = null;
      this.failures = this.threshold - 1;
      return true;
    }
    return false;
  }

  recordSuccess(): void {
    this.failures = 0;
    this.openedAt = null;
  }

  recordFailure(): void {
    this.failures += 1;
    if (this.failures >= this.threshold) this.openedAt = this.now();
  }

  get isOpen(): boolean {
    return (
      this.openedAt !== null && this.now() - this.openedAt < this.cooldownMs
    );
  }
}
