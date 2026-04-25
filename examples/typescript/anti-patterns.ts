// Anti-patterns vs correct patterns for FC/IS architecture.

// ============================================================
// 1. Raw `any` in core
// ============================================================

// ANTI-PATTERN: Core function accepts `any`
function calculateShippingBad(order: any): number {
  return order.weight * 0.5; // no type safety, crashes on missing field
}

// CORRECT: Core function accepts typed domain value
interface ShippingOrder {
  readonly weightKg: number;
}

function calculateShipping(order: ShippingOrder): number {
  return order.weightKg < 10 ? order.weightKg * 0.5 : order.weightKg * 0.3;
}

// ============================================================
// 2. Validation instead of parsing
// ============================================================

// ANTI-PATTERN: Returns boolean, caller still has untyped value
function isValidQuantity(q: unknown): boolean {
  return typeof q === "number" && q > 0;
}

function processBad(raw: Record<string, unknown>): void {
  if (isValidQuantity(raw.qty)) {
    console.log((raw.qty as number) * 2); // type assertion needed — smell
  }
}

// CORRECT: Returns typed value or error
type Quantity = number & { readonly __brand: "Quantity" };

function parseQuantity(raw: unknown): Quantity | { error: string } {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 1) {
    return { error: `invalid quantity: ${JSON.stringify(raw)}` };
  }
  return raw as Quantity;
}

// ============================================================
// 3. I/O in core
// ============================================================

// ANTI-PATTERN: Core reads environment directly
function getDiscountBad(price: number): number {
  const rate = Number(process.env.DISCOUNT_RATE ?? "0");
  return price * (1 - rate);
}

// CORRECT: Core receives rate as parameter
function getDiscount(price: number, discountRate: number): number {
  return price * (1 - discountRate);
}

// ============================================================
// 4. Mocking pure functions
// ============================================================

// ANTI-PATTERN: Test mocks a pure function's internals
// jest.spyOn(module, 'internalHelper').mockReturnValue(42);
// expect(calculate(10)).toBe(420); // coupled to implementation

// CORRECT: Test pure functions by input/output
// assert.equal(calculateShipping({ weightKg: 5 }), 2.5);
// assert.equal(calculateShipping({ weightKg: 15 }), 4.5);

export { calculateShipping, parseQuantity, getDiscount };
