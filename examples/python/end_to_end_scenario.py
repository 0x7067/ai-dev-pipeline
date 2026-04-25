"""Full pipeline: parse request → core logic → serialize response."""
from dataclasses import dataclass
from typing import Tuple
import json


# --- Domain types ---

@dataclass(frozen=True)
class CreateUserRequest:
    name: str
    email: str
    age: int

@dataclass(frozen=True)
class User:
    id: int
    name: str
    email: str
    age: int


# --- Boundary: parse ---

@dataclass
class ApiError:
    code: int
    message: str

def parse_create_user(raw: dict) -> Tuple[CreateUserRequest | None, ApiError | None]:
    name = raw.get("name")
    if not isinstance(name, str) or len(name.strip()) < 1:
        return None, ApiError(400, "name is required")

    email = raw.get("email")
    if not isinstance(email, str) or "@" not in email:
        return None, ApiError(400, "valid email is required")

    age = raw.get("age")
    if not isinstance(age, int) or age < 0 or age > 150:
        return None, ApiError(400, "age must be 0-150")

    return CreateUserRequest(name=name.strip(), email=email.strip(), age=age), None


# --- Core: pure logic ---

_next_id = 0

def create_user(req: CreateUserRequest, next_id: int) -> User:
    return User(id=next_id, name=req.name, email=req.email, age=req.age)


# --- Boundary: serialize ---

def serialize_user(user: User) -> dict:
    return {"id": user.id, "name": user.name, "email": user.email, "age": user.age}

def serialize_error(err: ApiError) -> dict:
    return {"error": {"code": err.code, "message": err.message}}


# --- Shell: HTTP-like handler ---

def handle_create_user(raw_body: str, next_id: int) -> Tuple[int, str]:
    try:
        raw = json.loads(raw_body)
    except json.JSONDecodeError:
        return 400, json.dumps(serialize_error(ApiError(400, "invalid JSON")))

    if not isinstance(raw, dict):
        return 400, json.dumps(serialize_error(ApiError(400, "expected object")))

    req, err = parse_create_user(raw)
    if err:
        return err.code, json.dumps(serialize_error(err))

    user = create_user(req, next_id)

    return 201, json.dumps(serialize_user(user))


if __name__ == "__main__":
    cases = [
        '{"name": "Alice", "email": "alice@example.com", "age": 30}',
        '{"name": "", "email": "bad", "age": -1}',
        'not json',
    ]
    for body in cases:
        status, response = handle_create_user(body, next_id=1)
        print(f"  {status}: {response}")
