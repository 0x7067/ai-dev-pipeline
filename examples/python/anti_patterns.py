"""Anti-patterns vs correct patterns for FC/IS architecture."""
from dataclasses import dataclass
import os
import json


# ============================================================
# 1. Raw data in core
# ============================================================

# ANTI-PATTERN: Core function receives raw dict from HTTP layer
def calculate_shipping_bad(raw_order: dict) -> float:
    weight = raw_order["weight"]  # KeyError if missing
    return weight * 0.5 if weight < 10 else weight * 0.3


# CORRECT: Core function receives parsed domain type
@dataclass(frozen=True)
class ShippingOrder:
    weight_kg: float

def calculate_shipping(order: ShippingOrder) -> float:
    return order.weight_kg * 0.5 if order.weight_kg < 10 else order.weight_kg * 0.3


# ============================================================
# 2. Validation instead of parsing
# ============================================================

# ANTI-PATTERN: Returns bool, caller still uses raw string
def is_valid_quantity(q: object) -> bool:
    return isinstance(q, int) and q > 0

def process_bad(raw: dict) -> None:
    if is_valid_quantity(raw["qty"]):
        print(raw["qty"] * 2)  # raw["qty"] is still untyped


# CORRECT: Returns parsed value or error
@dataclass(frozen=True)
class Quantity:
    value: int

def parse_quantity(raw: object) -> Quantity:
    if not isinstance(raw, int) or raw < 1:
        raise ValueError(f"invalid quantity: {raw!r}")
    return Quantity(value=raw)


# ============================================================
# 3. I/O in core
# ============================================================

# ANTI-PATTERN: Core reads environment directly
def get_discount_bad(price: float) -> float:
    rate = float(os.environ.get("DISCOUNT_RATE", "0"))
    return price * (1 - rate)


# CORRECT: Core receives discount rate as parameter
def get_discount(price: float, discount_rate: float) -> float:
    return price * (1 - discount_rate)


# ============================================================
# 4. Testing implementation details
# ============================================================

# ANTI-PATTERN: Test mocks internal structure of pure function
# def test_bad():
#     with mock.patch("module.INTERNAL_CONSTANT", 42):
#         assert calculate(10) == 420  # Coupled to implementation

# CORRECT: Test input/output of pure function directly
# def test_good():
#     assert calculate_shipping(ShippingOrder(weight_kg=5)) == 2.5
#     assert calculate_shipping(ShippingOrder(weight_kg=15)) == 4.5
