//! Contract tests: accept/reject matrix and round-trip serialization.
#![allow(dead_code)]

#[derive(Debug, Clone, PartialEq)]
struct Coordinate {
    lat: f64,
    lon: f64,
}

#[derive(Debug)]
struct CoordParseError(String);

fn parse_coordinate(lat: &str, lon: &str) -> Result<Coordinate, CoordParseError> {
    let lat: f64 = lat
        .trim()
        .parse()
        .map_err(|_| CoordParseError(format!("invalid lat: {lat:?}")))?;
    let lon: f64 = lon
        .trim()
        .parse()
        .map_err(|_| CoordParseError(format!("invalid lon: {lon:?}")))?;

    if !(-90.0..=90.0).contains(&lat) {
        return Err(CoordParseError(format!("lat out of range: {lat}")));
    }
    if !(-180.0..=180.0).contains(&lon) {
        return Err(CoordParseError(format!("lon out of range: {lon}")));
    }

    Ok(Coordinate { lat, lon })
}

fn serialize_coordinate(c: &Coordinate) -> String {
    format!("{},{}", c.lat, c.lon)
}

fn parse_serialized(s: &str) -> Result<Coordinate, CoordParseError> {
    let parts: Vec<&str> = s.split(',').collect();
    if parts.len() != 2 {
        return Err(CoordParseError("expected lat,lon format".into()));
    }
    parse_coordinate(parts[0], parts[1])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accept_valid_coordinates() {
        let cases = vec![
            ("0", "0", "origin"),
            ("90", "180", "max"),
            ("-90", "-180", "min"),
            ("40.7128", "-74.006", "NYC"),
        ];
        for (lat, lon, label) in cases {
            assert!(
                parse_coordinate(lat, lon).is_ok(),
                "should accept: {label}"
            );
        }
    }

    #[test]
    fn reject_invalid_coordinates() {
        let cases = vec![
            ("91", "0", "lat too high"),
            ("0", "181", "lon too high"),
            ("north", "0", "non-numeric lat"),
            ("", "", "empty"),
        ];
        for (lat, lon, label) in cases {
            assert!(
                parse_coordinate(lat, lon).is_err(),
                "should reject: {label}"
            );
        }
    }

    #[test]
    fn roundtrip_serialize_parse() {
        let cases = vec![
            Coordinate {
                lat: 0.0,
                lon: 0.0,
            },
            Coordinate {
                lat: 51.5074,
                lon: -0.1278,
            },
            Coordinate {
                lat: -33.8688,
                lon: 151.2093,
            },
        ];
        for original in cases {
            let serialized = serialize_coordinate(&original);
            let parsed = parse_serialized(&serialized).expect("round-trip should succeed");
            assert_eq!(parsed, original, "round-trip failed for {original:?}");
        }
    }
}
