---
name: test-gen
description: Generate tests with a focus on property-based core invariants and boundary contract behavior. Use when writing tests, defining invariants, or adding contract tests for boundary parsers.
---

# Test Generation

## Strategy by Layer

| Layer | Test type | What to verify |
|-------|-----------|---------------|
| **Core** | Unit + property-based | Pure logic, invariants, edge cases. No mocks. |
| **Boundary** | Contract tests | Parse accept/reject, round-trip consistency. |
| **Shell** | Integration tests | Wiring, I/O orchestration. Mocks acceptable. |

## Workflow

1. Identify core functions and list their invariants.
2. Identify boundary parsers and list their contracts.
3. Write property-based tests for core invariants.
4. Write contract tests for boundary parsers.
5. Add regression tests for known failures.
6. Run full suite and write output to `docs/test-report.md`.

## Common Invariants to Test

Use these as a checklist when examining core functions:

| Invariant | Description | Example |
|-----------|-------------|---------|
| **Idempotency** | `f(f(x)) == f(x)` | Normalizing whitespace, deduplicating a list |
| **Round-trip** | `parse(serialize(x)) == x` | JSON encode/decode, URL parse/format |
| **Commutativity** | `f(a, b) == f(b, a)` | Set union, total calculation independent of order |
| **Monotonicity** | If `a ≤ b` then `f(a) ≤ f(b)` | Pricing tiers, progressive tax brackets |
| **Invariant preservation** | Pre-condition holds → post-condition holds | Balance never negative, list stays sorted |
| **Identity element** | `f(x, identity) == x` | Adding zero, merging empty config |

## Property-Based Test Examples

```python
# Invariant: round-trip consistency for boundary parser
from hypothesis import given, strategies as st

@given(st.emails())
def test_email_roundtrip(raw_email):
    """parse(serialize(x)) == x"""
    parsed = Email.parse(raw_email)
    assert Email.parse(str(parsed)) == parsed

# Invariant: discount never exceeds original price
@given(
    price=st.decimals(min_value=0, max_value=10000, places=2),
    pct=st.decimals(min_value=0, max_value=100, places=1),
)
def test_discount_bounded(price, pct):
    """Discounted price is always in [0, original_price]"""
    result = apply_discount(price, pct)
    assert 0 <= result <= price

# Invariant: idempotency
@given(st.text())
def test_normalize_idempotent(text):
    """f(f(x)) == f(x)"""
    once = normalize_whitespace(text)
    twice = normalize_whitespace(once)
    assert once == twice
```

## Contract Test Examples

```python
# Contract: boundary parser accepts valid input
def test_parse_order_valid():
    raw = {"total": "19.99", "items": [{"sku": "A1", "qty": 1}]}
    order = parse_order(raw)
    assert isinstance(order, Order)
    assert order.total == Decimal("19.99")

# Contract: boundary parser rejects invalid input
def test_parse_order_missing_total():
    with pytest.raises(ParseError):
        parse_order({"items": [{"sku": "A1", "qty": 1}]})

def test_parse_order_negative_qty():
    with pytest.raises(ParseError):
        parse_order({"total": "10.00", "items": [{"sku": "A1", "qty": -1}]})

# Contract: round-trip serialization
def test_order_roundtrip():
    original = Order(total=Decimal("19.99"), items=[LineItem("A1", 1)])
    assert parse_order(serialize_order(original)) == original
```

## Data Generator Patterns

```python
# Build generators that match your domain types
valid_money = st.decimals(min_value=0, max_value=1_000_000, places=2)
valid_quantity = st.integers(min_value=1, max_value=9999)
valid_sku = st.from_regex(r"[A-Z]{2}[0-9]{4}", fullmatch=True)

valid_line_item = st.builds(LineItem, sku=valid_sku, qty=valid_quantity)
valid_order = st.builds(Order, total=valid_money, items=st.lists(valid_line_item, min_size=1))

# Invalid generators for reject tests
invalid_money = st.one_of(
    st.just(None),
    st.text().filter(lambda s: not s.replace(".", "").isdigit()),
    st.decimals(max_value=Decimal("-0.01")),
)
```

## Anti-Patterns

```
# ❌ WRONG — testing with mocks in core (core should be pure)
def test_calculate_total():
    mock_db = Mock()
    mock_db.get_tax_rate.return_value = 0.1
    result = calculate_total(mock_db, items)    # core depends on mock

# ✅ CORRECT — core tested with plain values
def test_calculate_total():
    result = calculate_total(items, tax_rate=Decimal("0.1"))
    assert result == expected

# ❌ WRONG — only testing happy path for parser
def test_parse_email():
    assert parse_email("user@example.com") is not None   # no reject tests

# ✅ CORRECT — testing both accept and reject
def test_parse_email_valid():
    assert parse_email("user@example.com").value == "user@example.com"

def test_parse_email_rejects_missing_at():
    with pytest.raises(ParseError):
        parse_email("userexample.com")
```

## Output

- `docs/test-report.md` with:
  - Coverage summary (core invariants, boundary contracts, regression).
  - Pass/fail counts.
  - Failures marked as blocking if invariants/contracts fail.
  - Flake triage notes when reruns are needed.
