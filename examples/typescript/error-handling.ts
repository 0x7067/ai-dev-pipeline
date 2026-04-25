// Result types and fail-closed error handling.

// --- Result type ---

type Result<T, E> = { readonly ok: true; readonly value: T } | { readonly ok: false; readonly error: E };

function ok<T>(value: T): Result<T, never> {
  return { ok: true, value };
}

function err<E>(error: E): Result<never, E> {
  return { ok: false, error };
}

// --- Domain types ---

type UserId = number & { readonly __brand: "UserId" };

function parseUserId(raw: unknown): Result<UserId, string> {
  if (typeof raw === "string") {
    const n = Number(raw);
    if (Number.isNaN(n)) return err(`cannot parse user id: ${JSON.stringify(raw)}`);
    raw = n;
  }
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 1) {
    return err(`user id must be a positive integer, got ${JSON.stringify(raw)}`);
  }
  return ok(raw as UserId);
}

// --- Core logic returning Result ---

const PERMISSIONS: Record<number, string[]> = { 1: ["read", "write"], 2: ["read"] };

function lookupPermissions(id: UserId): Result<string[], string> {
  const perms = PERMISSIONS[id];
  if (!perms) return err(`user ${id} not found`);
  return ok(perms);
}

// --- Fail-closed: deny by default on any error ---

function authorize(rawId: unknown, required: string): Result<true, string> {
  const idResult = parseUserId(rawId);
  if (!idResult.ok) return err(`access denied: ${idResult.error}`);

  const permsResult = lookupPermissions(idResult.value);
  if (!permsResult.ok) return err(`access denied: ${permsResult.error}`);

  if (!permsResult.value.includes(required)) {
    return err(`access denied: missing '${required}' permission`);
  }

  return ok(true);
}

export { Result, ok, err, UserId, parseUserId, lookupPermissions, authorize };
