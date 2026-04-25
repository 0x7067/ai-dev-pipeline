// Contract tests: accept/reject matrix and round-trip serialization.
package examples

import (
	"encoding/json"
	"testing"
)

func TestParseEmail_AcceptReject(t *testing.T) {
	accept := []struct {
		input string
		label string
	}{
		{"user@example.com", "simple"},
		{"first.last@sub.domain.co", "dotted"},
		{"a+tag@host.org", "plus tag"},
	}
	for _, tc := range accept {
		t.Run("accept/"+tc.label, func(t *testing.T) {
			_, err := ParseEmail(tc.input)
			if err != nil {
				t.Errorf("should accept %q: %v", tc.input, err)
			}
		})
	}

	reject := []struct {
		input string
		label string
	}{
		{"", "empty"},
		{"no-at-sign", "missing @"},
		{"@no-local.com", "missing local"},
		{"user@", "missing domain"},
	}
	for _, tc := range reject {
		t.Run("reject/"+tc.label, func(t *testing.T) {
			_, err := ParseEmail(tc.input)
			if err == nil {
				t.Errorf("should reject %q", tc.input)
			}
		})
	}
}

func TestParseCoordinate_AcceptReject(t *testing.T) {
	accept := []string{
		`{"lat": 0, "lon": 0}`,
		`{"lat": 90, "lon": 180}`,
		`{"lat": -90, "lon": -180}`,
		`{"lat": 40.7128, "lon": -74.006}`,
	}
	for _, raw := range accept {
		t.Run("accept", func(t *testing.T) {
			_, err := ParseCoordinate([]byte(raw))
			if err != nil {
				t.Errorf("should accept %s: %v", raw, err)
			}
		})
	}

	reject := []string{
		`{"lat": 91, "lon": 0}`,
		`{"lat": 0, "lon": 181}`,
		`{"lat": "north"}`,
		`{}`,
		`not json`,
	}
	for _, raw := range reject {
		t.Run("reject", func(t *testing.T) {
			_, err := ParseCoordinate([]byte(raw))
			if err == nil {
				t.Errorf("should reject %s", raw)
			}
		})
	}
}

func TestCoordinate_JSONRoundTrip(t *testing.T) {
	original := Coordinate{Lat: 51.5074, Lon: -0.1278}
	data, err := json.Marshal(original)
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := ParseCoordinate(data)
	if err != nil {
		t.Fatal(err)
	}
	if parsed != original {
		t.Errorf("round-trip failed: got %+v, want %+v", parsed, original)
	}
}
