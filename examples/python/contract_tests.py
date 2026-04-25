"""Contract tests for boundary parsers: accept/reject matrix and round-trip checks."""
import json
import unittest
from dataclasses import dataclass, asdict
from typing import Tuple


@dataclass(frozen=True)
class Coordinate:
    lat: float
    lon: float

@dataclass
class ParseError:
    field: str
    message: str

def parse_coordinate(raw: dict) -> Tuple[Coordinate | None, ParseError | None]:
    lat = raw.get("lat")
    if not isinstance(lat, (int, float)) or lat < -90 or lat > 90:
        return None, ParseError("lat", "must be a number between -90 and 90")
    lon = raw.get("lon")
    if not isinstance(lon, (int, float)) or lon < -180 or lon > 180:
        return None, ParseError("lon", "must be a number between -180 and 180")
    return Coordinate(lat=float(lat), lon=float(lon)), None

def serialize_coordinate(c: Coordinate) -> dict:
    return asdict(c)


class AcceptRejectContract(unittest.TestCase):
    accept_cases = [
        ({"lat": 0, "lon": 0}, "origin"),
        ({"lat": 90, "lon": 180}, "max values"),
        ({"lat": -90, "lon": -180}, "min values"),
        ({"lat": 40.7128, "lon": -74.006}, "NYC"),
    ]

    reject_cases = [
        ({"lat": 91, "lon": 0}, "lat too high"),
        ({"lat": 0, "lon": 181}, "lon too high"),
        ({"lat": "north", "lon": 0}, "lat not a number"),
        ({}, "missing fields"),
        ({"lat": None, "lon": None}, "null values"),
    ]

    def test_accept(self):
        for raw, label in self.accept_cases:
            with self.subTest(label):
                coord, err = parse_coordinate(raw)
                self.assertIsNotNone(coord, f"should accept: {label}")
                self.assertIsNone(err)

    def test_reject(self):
        for raw, label in self.reject_cases:
            with self.subTest(label):
                coord, err = parse_coordinate(raw)
                self.assertIsNone(coord, f"should reject: {label}")
                self.assertIsNotNone(err)


class RoundTripContract(unittest.TestCase):
    def test_parse_serialize_roundtrip(self):
        cases = [
            {"lat": 0.0, "lon": 0.0},
            {"lat": 40.7128, "lon": -74.006},
            {"lat": -33.8688, "lon": 151.2093},
        ]
        for raw in cases:
            coord, _ = parse_coordinate(raw)
            self.assertIsNotNone(coord)
            serialized = serialize_coordinate(coord)
            self.assertEqual(serialized, raw)

    def test_json_roundtrip(self):
        raw = {"lat": 51.5074, "lon": -0.1278}
        coord, _ = parse_coordinate(raw)
        json_str = json.dumps(serialize_coordinate(coord))
        reparsed, _ = parse_coordinate(json.loads(json_str))
        self.assertEqual(coord, reparsed)


if __name__ == "__main__":
    unittest.main()
