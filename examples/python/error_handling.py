"""Result types and fail-closed error handling without exceptions as flow control."""
from dataclasses import dataclass
from typing import Generic, TypeVar, Union

T = TypeVar("T")
E = TypeVar("E")


@dataclass(frozen=True)
class Ok(Generic[T]):
    value: T
    ok: bool = True

@dataclass(frozen=True)
class Err(Generic[E]):
    error: E
    ok: bool = False

Result = Union[Ok[T], Err[E]]


# --- Boundary parser returning Result ---

@dataclass(frozen=True)
class UserId:
    value: int

def parse_user_id(raw: object) -> Result[UserId, str]:
    if not isinstance(raw, (int, str)):
        return Err(f"expected int or numeric string, got {type(raw).__name__}")
    try:
        n = int(raw)
    except (ValueError, TypeError):
        return Err(f"cannot convert {raw!r} to integer")
    if n < 1:
        return Err(f"user id must be positive, got {n}")
    return Ok(UserId(value=n))


# --- Core logic using Result (no exceptions) ---

def lookup_permissions(user_id: UserId) -> Result[list[str], str]:
    known = {1: ["read", "write"], 2: ["read"]}
    perms = known.get(user_id.value)
    if perms is None:
        return Err(f"user {user_id.value} not found")
    return Ok(perms)


# --- Fail-closed: deny by default on any error ---

def authorize(raw_id: object, required: str) -> Result[bool, str]:
    result = parse_user_id(raw_id)
    if not result.ok:
        return Err(f"access denied: {result.error}")

    perms = lookup_permissions(result.value)
    if not perms.ok:
        return Err(f"access denied: {perms.error}")

    if required not in perms.value:
        return Err(f"access denied: missing {required!r} permission")

    return Ok(True)


if __name__ == "__main__":
    for raw in [1, 2, 3, "abc", -1]:
        result = authorize(raw, "write")
        if result.ok:
            print(f"  {raw} -> authorized")
        else:
            print(f"  {raw} -> {result.error}")
