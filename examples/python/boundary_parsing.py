"""Parse, don't validate: convert raw input to typed domain values or structured errors."""
from dataclasses import dataclass
from typing import Tuple
import re


@dataclass(frozen=True)
class Email:
    local: str
    domain: str

    def __str__(self) -> str:
        return f"{self.local}@{self.domain}"

@dataclass
class ParseError:
    field: str
    message: str


# --- CORRECT: Parse into a typed value ---

_EMAIL_RE = re.compile(r"^([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})$")

def parse_email(raw: str) -> Tuple[Email | None, ParseError | None]:
    raw = raw.strip()
    match = _EMAIL_RE.match(raw)
    if not match:
        return None, ParseError("email", f"invalid email format: {raw!r}")
    return Email(local=match.group(1), domain=match.group(2)), None


@dataclass(frozen=True)
class Age:
    value: int

def parse_age(raw: object) -> Tuple[Age | None, ParseError | None]:
    if not isinstance(raw, int) or raw < 0 or raw > 150:
        return None, ParseError("age", f"must be an integer 0-150, got {raw!r}")
    return Age(value=raw), None


# --- ANTI-PATTERN: Validate then use raw data ---

def is_valid_email(raw: str) -> bool:
    """Validation returns bool — caller still has an untyped string."""
    return bool(_EMAIL_RE.match(raw.strip()))

def send_welcome(raw_email: str) -> None:
    """Bug-prone: uses raw string after a bool check somewhere upstream."""
    if is_valid_email(raw_email):
        print(f"Sending to {raw_email}")  # raw_email could have spaces, etc.


# --- CORRECT: Use parsed value ---

def send_welcome_safe(email: Email) -> None:
    """Type-safe: only accepts already-parsed Email."""
    print(f"Sending to {email}")


if __name__ == "__main__":
    email, err = parse_email("  user@example.com  ")
    if email:
        send_welcome_safe(email)
    age, err = parse_age(25)
    if age:
        print(f"Age: {age.value}")
