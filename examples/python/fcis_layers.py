"""FC/IS layers: pure core, boundary parser, and shell orchestrator."""
from dataclasses import dataclass
from typing import Tuple
import json
import os


# --- Core (pure, no I/O) ---

@dataclass(frozen=True)
class Order:
    product: str
    quantity: int
    unit_price: float

def calculate_total(order: Order, tax_rate: float) -> float:
    subtotal = order.quantity * order.unit_price
    return round(subtotal * (1 + tax_rate), 2)


# --- Boundary (parse raw data into domain types) ---

@dataclass
class ParseError:
    field: str
    message: str

def parse_order(raw: dict) -> Tuple[Order | None, ParseError | None]:
    product = raw.get("product")
    if not isinstance(product, str) or not product.strip():
        return None, ParseError("product", "must be a non-empty string")

    quantity = raw.get("quantity")
    if not isinstance(quantity, int) or quantity < 1:
        return None, ParseError("quantity", "must be a positive integer")

    unit_price = raw.get("unit_price")
    if not isinstance(unit_price, (int, float)) or unit_price < 0:
        return None, ParseError("unit_price", "must be a non-negative number")

    return Order(product=product.strip(), quantity=quantity, unit_price=float(unit_price)), None


# --- Shell (I/O, orchestration) ---

def process_order_file(path: str) -> str:
    with open(path) as f:
        raw = json.load(f)

    tax_rate = float(os.environ.get("TAX_RATE", "0.1"))

    order, err = parse_order(raw)
    if err:
        return f"Error in {err.field}: {err.message}"

    total = calculate_total(order, tax_rate)
    return f"Order total for {order.product}: ${total}"


if __name__ == "__main__":
    raw = {"product": "Widget", "quantity": 3, "unit_price": 9.99}
    order, err = parse_order(raw)
    if order:
        print(f"Total: ${calculate_total(order, 0.1)}")
