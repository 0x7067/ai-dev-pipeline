// FC/IS layers: pure core, boundary parser, and shell orchestrator.
import { readFileSync } from "node:fs";

// --- Domain types ---

interface Order {
  readonly product: string;
  readonly quantity: number;
  readonly unitPrice: number;
}

interface ParseError {
  readonly field: string;
  readonly message: string;
}

// --- Core (pure, no I/O) ---

function calculateTotal(order: Order, taxRate: number): number {
  const subtotal = order.quantity * order.unitPrice;
  return Math.round(subtotal * (1 + taxRate) * 100) / 100;
}

// --- Boundary (parse raw data into domain types) ---

function parseOrder(raw: unknown): Order | ParseError {
  if (typeof raw !== "object" || raw === null) {
    return { field: "body", message: "expected an object" };
  }
  const obj = raw as Record<string, unknown>;

  if (typeof obj.product !== "string" || obj.product.trim() === "") {
    return { field: "product", message: "must be a non-empty string" };
  }
  if (typeof obj.quantity !== "number" || !Number.isInteger(obj.quantity) || obj.quantity < 1) {
    return { field: "quantity", message: "must be a positive integer" };
  }
  if (typeof obj.unitPrice !== "number" || obj.unitPrice < 0) {
    return { field: "unitPrice", message: "must be a non-negative number" };
  }

  return {
    product: obj.product.trim(),
    quantity: obj.quantity,
    unitPrice: obj.unitPrice,
  };
}

function isParseError(v: Order | ParseError): v is ParseError {
  return "field" in v && "message" in v && !("product" in v);
}

// --- Shell (I/O, orchestration) ---

function processOrderFile(path: string): string {
  const data = JSON.parse(readFileSync(path, "utf-8"));
  const result = parseOrder(data);

  if (isParseError(result)) {
    return `Error in ${result.field}: ${result.message}`;
  }

  const taxRate = Number(process.env.TAX_RATE ?? "0.1");
  return `Order total for ${result.product}: $${calculateTotal(result, taxRate)}`;
}

export { Order, ParseError, calculateTotal, parseOrder, isParseError, processOrderFile };
