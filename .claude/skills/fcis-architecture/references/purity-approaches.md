# Purity Approaches: How Core Handles I/O Dependencies

When core logic needs data that comes from I/O, there are three approaches with increasing purity. Choose based on project needs.

## Approach 1: Shell Decides (~30% pure)

Shell performs I/O and makes the decision. Core is unaware.

```python
# Shell
async def handle_signup(request):
    user = parse_signup(request.json)
    if await db.email_exists(user.email):    # decision lives in shell
        return error("exists")
    await db.create_user(user)

# Core — only has the "easy" logic
def validate_password(pw: str) -> bool:
    return len(pw) >= 8
```

**Tradeoff:** Business logic leaks into shell. Shell tests need mocks.
**Use for:** Simple constraint checks, MVPs, teams new to FC/IS.

## Approach 2: Capability Injection (~60% pure) — Recommended Default

Shell fetches I/O results and passes them as values. Core makes all decisions.

```python
# Core — pure, owns the decision
def process_signup(user: ValidUser, email_exists: bool) -> SignupResult:
    if email_exists:
        return SignupRejected("email taken")
    return SignupApproved(user)

# Shell — fetches data, calls core
async def handle_signup(request):
    user = parse_signup(request.json)
    exists = await db.email_exists(user.email)
    result = process_signup(user, exists)   # pure call
    match result:
        case SignupApproved(u): await db.create_user(u)
        case SignupRejected(r): return error(r)
```

**Tradeoff:** Function signatures grow. Straightforward for most cases.
**Use for:** Most projects. Default choice.

## Approach 3: Event/Command Pattern (~95% pure)

Core returns commands describing needed side effects. Shell interprets them.

```python
# Core — returns instructions, never does I/O
def start_signup(user: ValidUser) -> Command:
    return CheckEmail(
        email=user.email,
        on_exists=SignupRejected("email taken"),
        on_available=CreateUser(user),
    )

# Shell — interpreter loop
async def run(cmd: Command):
    match cmd:
        case CheckEmail(email, on_exists, on_available):
            if await db.email_exists(email):
                await run(on_exists)
            else:
                await run(on_available)
        case CreateUser(user):
            await db.create_user(user)
        case SignupRejected(reason):
            log.info(reason)
```

**Tradeoff:** Most complex. More boilerplate. Full audit trail.
**Use for:** Complex workflows, audit/compliance, event sourcing.

## Decision Guide

| Question | Answer | Approach |
|----------|--------|----------|
| Is this a simple pre-check before core logic? | Yes | 1 — Shell Decides |
| Does core need to own the business rule? | Yes | 2 — Capabilities |
| Do you need an audit trail of every decision? | Yes | 3 — Events |
| Unsure? | — | **Start with 2** |

Most projects use a hybrid: Approach 1 for trivial checks, Approach 2 as default, Approach 3 for critical paths.

## Sources

- [Choosing Your Purity Level — Future Iteration](https://blog.futureiteration.dev/articles/functional-core-imperative-shell-part-3-choosing-your-purity-level/)
- [The Functional Core, Imperative Shell Pattern — Kenneth Lange](https://kennethlange.com/functional-core-imperative-shell/)
- [FC/IS — kbilsted](https://github.com/kbilsted/Functional-core-imperative-shell)
