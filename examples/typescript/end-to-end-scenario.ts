// Full pipeline: parse request → core logic → serialize response.

// --- Domain types ---

interface CreateUserRequest {
  readonly name: string;
  readonly email: string;
  readonly age: number;
}

interface User {
  readonly id: number;
  readonly name: string;
  readonly email: string;
  readonly age: number;
}

interface ApiError {
  readonly code: number;
  readonly message: string;
}

interface ParseError {
  readonly field: string;
  readonly message: string;
}

// --- Boundary: parse ---

function parseCreateUser(raw: unknown): CreateUserRequest | ParseError {
  if (typeof raw !== "object" || raw === null) {
    return { field: "body", message: "expected an object" };
  }
  const obj = raw as Record<string, unknown>;

  if (typeof obj.name !== "string" || obj.name.trim() === "") {
    return { field: "name", message: "required non-empty string" };
  }
  if (typeof obj.email !== "string" || !obj.email.includes("@")) {
    return { field: "email", message: "valid email required" };
  }
  if (typeof obj.age !== "number" || !Number.isInteger(obj.age) || obj.age < 0 || obj.age > 150) {
    return { field: "age", message: "must be integer 0-150" };
  }
  return { name: obj.name.trim(), email: obj.email.trim(), age: obj.age };
}

function isParseError(v: CreateUserRequest | ParseError): v is ParseError {
  return "field" in v && "message" in v && !("name" in v);
}

// --- Core: pure logic ---

function createUser(req: CreateUserRequest, nextId: number): User {
  return { id: nextId, name: req.name, email: req.email, age: req.age };
}

// --- Boundary: serialize ---

function serializeUser(user: User): Record<string, unknown> {
  return { id: user.id, name: user.name, email: user.email, age: user.age };
}

function serializeApiError(err: ApiError): Record<string, unknown> {
  return { error: { code: err.code, message: err.message } };
}

// --- Shell: HTTP-like handler ---

function handleCreateUser(rawBody: string, nextId: number): { status: number; body: string } {
  let raw: unknown;
  try {
    raw = JSON.parse(rawBody);
  } catch {
    return { status: 400, body: JSON.stringify(serializeApiError({ code: 400, message: "invalid JSON" })) };
  }

  const parsed = parseCreateUser(raw);
  if (isParseError(parsed)) {
    return {
      status: 400,
      body: JSON.stringify(serializeApiError({ code: 400, message: `${parsed.field}: ${parsed.message}` })),
    };
  }

  const user = createUser(parsed, nextId);
  return { status: 201, body: JSON.stringify(serializeUser(user)) };
}

export { handleCreateUser, createUser, parseCreateUser };
