// Property-based testing with node:test and manual random generation.
import { describe, it } from "node:test";
import assert from "node:assert/strict";

// --- Functions under test ---

function applyDiscount(cents: number, pct: number): number {
  const clampedPct = Math.max(0, Math.min(100, Math.floor(pct)));
  return Math.floor(cents * (100 - clampedPct) / 100);
}

function addMoney(a: number, b: number): number {
  return a + b;
}

// --- Simple RNG for reproducible tests ---

function randomInts(seed: number, count: number, max: number): number[] {
  const values: number[] = [];
  let state = seed;
  for (let i = 0; i < count; i++) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    values.push(state % max);
  }
  return values;
}

const ITERATIONS = 200;

describe("property: applyDiscount", () => {
  it("result is bounded between 0 and original", () => {
    const cents = randomInts(42, ITERATIONS, 1_000_000);
    const pcts = randomInts(43, ITERATIONS, 101);
    for (let i = 0; i < ITERATIONS; i++) {
      const result = applyDiscount(cents[i], pcts[i]);
      assert.ok(result >= 0, `result ${result} should be >= 0`);
      assert.ok(result <= cents[i], `result ${result} should be <= ${cents[i]}`);
    }
  });

  it("0% discount is identity", () => {
    for (const c of randomInts(44, ITERATIONS, 1_000_000)) {
      assert.equal(applyDiscount(c, 0), c);
    }
  });

  it("100% discount is zero", () => {
    for (const c of randomInts(45, ITERATIONS, 1_000_000)) {
      assert.equal(applyDiscount(c, 100), 0);
    }
  });

  it("monotonic: higher discount → lower result", () => {
    const cents = randomInts(46, ITERATIONS, 1_000_000);
    const lo = randomInts(47, ITERATIONS, 100);
    const hi = randomInts(48, ITERATIONS, 100);
    for (let i = 0; i < ITERATIONS; i++) {
      const [a, b] = lo[i] <= hi[i] ? [lo[i], hi[i]] : [hi[i], lo[i]];
      assert.ok(applyDiscount(cents[i], a) >= applyDiscount(cents[i], b));
    }
  });
});

describe("property: addMoney", () => {
  it("commutative", () => {
    const a = randomInts(49, ITERATIONS, 100_000);
    const b = randomInts(50, ITERATIONS, 100_000);
    for (let i = 0; i < ITERATIONS; i++) {
      assert.equal(addMoney(a[i], b[i]), addMoney(b[i], a[i]));
    }
  });
});
