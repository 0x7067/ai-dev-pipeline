---
name: fcis-architecture
description: Apply Functional Core / Imperative Shell architecture and enforce parse-at-boundary design. Use when classifying code into core/shell/boundary layers, designing new modules, or enforcing separation of side effects.
---

# FC/IS Architecture

## Objective

Keep business decisions deterministic and side effects isolated.

## Layer Definitions

| Layer | Responsibility | May call | Must not |
|-------|---------------|----------|----------|
| **Core** | Pure business logic, decisions, transformations | Other core functions | Import shell, perform I/O, read ambient state |
| **Shell** | Orchestration, I/O, side effects | Core and external systems | Contain business decisions or conditionals beyond routing |
| **Boundary** | Parse untrusted input into trusted domain types | Core types/constructors | Pass raw data through to core |

## Rules

- Core is pure and deterministic.
- Shell handles side effects and orchestration.
- Boundary parses untrusted input into trusted domain types.
- Time/random/id are passed in, not read from ambient APIs in core.
- Shell can call core. Core cannot call shell and is unaware of its existence.
- When unsure where code belongs, make it pure and put it in core.

## Layer Decision Tree

```
Is this code performing I/O (DB, network, file, stdin/stdout)?
├── Yes → SHELL
└── No
    Is this code parsing/validating external input into domain types?
    ├── Yes → BOUNDARY
    └── No
        Does it make a business decision or transform data?
        ├── Yes → CORE
        └── No → Likely SHELL (coordination/wiring)
```

## Anti-Patterns

### 1. Side effects in core

```
# ❌ WRONG — core reads from DB
def get_expired_users():
    users = db.get_all_users()          # I/O in core
    now = datetime.now()                 # ambient state
    return [u for u in users if u.expiry <= now]

# ✅ CORRECT — core receives data, returns decisions
def get_expired_users(users: list[User], now: datetime) -> list[User]:
    return [u for u in users if u.expiry <= now]

# Shell orchestrates
expired = get_expired_users(db.get_all_users(), datetime.now())
```

### 2. Raw external data in core

```
# ❌ WRONG — core operates on raw dict from API
def calculate_discount(order_json: dict) -> float:
    return order_json["total"] * 0.1     # trusts raw input

# ✅ CORRECT — boundary parses first, core receives typed value
@dataclass(frozen=True)
class Order:
    total: Decimal
    items: list[LineItem]

def parse_order(raw: dict) -> Order:    # BOUNDARY
    ...

def calculate_discount(order: Order) -> Decimal:  # CORE
    return order.total * Decimal("0.1")
```

### 3. Business logic in shell

```
# ❌ WRONG — shell contains business decision
async def handle_signup(request):
    user = parse_signup(request.json)
    if await db.email_exists(user.email):   # decision in shell
        return error_response("exists")
    await db.create_user(user)

# ✅ CORRECT — core owns the decision via capability injection
def process_signup(user: ValidUser, email_exists: bool) -> SignupResult:
    if email_exists:                         # decision in core
        return SignupRejected("email taken")
    return SignupApproved(user)

# Shell provides data, core decides
async def handle_signup(request):
    user = parse_signup(request.json)
    exists = await db.email_exists(user.email)
    result = process_signup(user, exists)    # pure call
    ...
```

### 4. Validation instead of parsing at boundary

```
# ❌ WRONG — validates then discards the proof
def is_valid_email(s: str) -> bool:
    return "@" in s and "." in s

# ✅ CORRECT — parses into a type that proves validity
class Email:
    def __init__(self, raw: str):
        if "@" not in raw or "." not in raw:
            raise ValueError(f"Invalid email: {raw}")
        self.value = raw
```

## Testing Strategy by Layer

| Layer | Test type | Approach |
|-------|-----------|----------|
| **Core** | Unit + property-based | Pure functions — no mocks, no I/O. Test with explicit inputs/outputs. Fuzz with property-based generators. |
| **Boundary** | Contract tests | Verify accept/reject for valid/invalid inputs. Round-trip: `parse(serialize(x)) == x`. |
| **Shell** | Integration tests | Test wiring and I/O. Mocks acceptable here. Fewer paths, more dependencies. |

## Deliverable Expectations

- Every proposed change includes layer classification.
- Core invariants are listed for property-based testing.
- Boundary parsers are identified before implementation.

## References

- [Boundaries — Gary Bernhardt (SCNA 2012)](https://www.destroyallsoftware.com/talks/boundaries)
- [Parse, Don't Validate — Alexis King](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
- [Google Testing Blog — Functional Core, Imperative Shell](https://testing.googleblog.com/2025/10/simplify-your-code-functional-core.html)
- [Pragmint — FC/IS Open Practice](https://github.com/pragmint/open-practices/blob/main/practices/follow-functional-core-imperative-shell.md)
- [Purity Levels & Approaches](./references/purity-approaches.md)
