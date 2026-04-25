// Parse, don't validate: branded types and type guard parsers.

// --- Branded types ---

type Email = string & { readonly __brand: "Email" };
type Age = number & { readonly __brand: "Age" };

interface ParseError {
  readonly field: string;
  readonly message: string;
}

// --- Parsing (returns typed value or error) ---

const EMAIL_RE = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;

function parseEmail(raw: unknown): Email | ParseError {
  if (typeof raw !== "string") {
    return { field: "email", message: "must be a string" };
  }
  const trimmed = raw.trim();
  if (!EMAIL_RE.test(trimmed)) {
    return { field: "email", message: `invalid email format: ${JSON.stringify(trimmed)}` };
  }
  return trimmed as Email;
}

function parseAge(raw: unknown): Age | ParseError {
  if (typeof raw !== "number" || !Number.isInteger(raw)) {
    return { field: "age", message: "must be an integer" };
  }
  if (raw < 0 || raw > 150) {
    return { field: "age", message: `must be 0-150, got ${raw}` };
  }
  return raw as Age;
}

function isParseError(v: unknown): v is ParseError {
  return typeof v === "object" && v !== null && "field" in v && "message" in v;
}

// --- ANTI-PATTERN: Validate, then use raw ---

function isValidEmail(raw: string): boolean {
  return EMAIL_RE.test(raw.trim()); // caller still has untyped string
}

function sendWelcomeBad(raw: string): void {
  if (isValidEmail(raw)) {
    console.log(`Sending to ${raw}`); // raw could have spaces, etc.
  }
}

// --- CORRECT: Use parsed value ---

function sendWelcome(email: Email): void {
  console.log(`Sending to ${email}`);
}

export { Email, Age, ParseError, parseEmail, parseAge, isParseError, sendWelcome };
