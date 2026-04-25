// Contract tests: accept/reject matrix and round-trip serialization.
import { describe, it } from "node:test";
import assert from "node:assert/strict";

// --- Parser under test ---

interface Coordinate {
  readonly lat: number;
  readonly lon: number;
}

interface ParseError {
  readonly field: string;
  readonly message: string;
}

function parseCoordinate(raw: unknown): Coordinate | ParseError {
  if (typeof raw !== "object" || raw === null) {
    return { field: "body", message: "expected an object" };
  }
  const obj = raw as Record<string, unknown>;

  if (typeof obj.lat !== "number" || obj.lat < -90 || obj.lat > 90) {
    return { field: "lat", message: "must be a number between -90 and 90" };
  }
  if (typeof obj.lon !== "number" || obj.lon < -180 || obj.lon > 180) {
    return { field: "lon", message: "must be a number between -180 and 180" };
  }
  return { lat: obj.lat, lon: obj.lon };
}

function isParseError(v: Coordinate | ParseError): v is ParseError {
  return "field" in v && "message" in v && !("lat" in v);
}

function serializeCoordinate(c: Coordinate): Record<string, number> {
  return { lat: c.lat, lon: c.lon };
}

// --- Tests ---

describe("parseCoordinate: accept/reject", () => {
  const accept = [
    { input: { lat: 0, lon: 0 }, label: "origin" },
    { input: { lat: 90, lon: 180 }, label: "max values" },
    { input: { lat: -90, lon: -180 }, label: "min values" },
    { input: { lat: 40.7128, lon: -74.006 }, label: "NYC" },
  ];

  for (const { input, label } of accept) {
    it(`accepts: ${label}`, () => {
      const result = parseCoordinate(input);
      assert.ok(!isParseError(result), `should accept: ${label}`);
    });
  }

  const reject = [
    { input: { lat: 91, lon: 0 }, label: "lat too high" },
    { input: { lat: 0, lon: 181 }, label: "lon too high" },
    { input: { lat: "north", lon: 0 }, label: "lat not a number" },
    { input: {}, label: "missing fields" },
    { input: null, label: "null" },
  ];

  for (const { input, label } of reject) {
    it(`rejects: ${label}`, () => {
      const result = parseCoordinate(input);
      assert.ok(isParseError(result), `should reject: ${label}`);
    });
  }
});

describe("parseCoordinate: round-trip", () => {
  it("parse → serialize → parse preserves value", () => {
    const cases = [
      { lat: 0, lon: 0 },
      { lat: 40.7128, lon: -74.006 },
      { lat: -33.8688, lon: 151.2093 },
    ];
    for (const raw of cases) {
      const parsed = parseCoordinate(raw);
      assert.ok(!isParseError(parsed));
      const serialized = serializeCoordinate(parsed);
      const reparsed = parseCoordinate(serialized);
      assert.ok(!isParseError(reparsed));
      assert.deepEqual(reparsed, parsed);
    }
  });

  it("JSON round-trip", () => {
    const raw = { lat: 51.5074, lon: -0.1278 };
    const parsed = parseCoordinate(raw);
    assert.ok(!isParseError(parsed));
    const json = JSON.stringify(serializeCoordinate(parsed));
    const reparsed = parseCoordinate(JSON.parse(json));
    assert.ok(!isParseError(reparsed));
    assert.deepEqual(reparsed, parsed);
  });
});
