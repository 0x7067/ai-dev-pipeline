// Parse, don't validate: convert raw JSON to typed domain values or structured errors.
package examples

import (
	"encoding/json"
	"fmt"
	"regexp"
)

// --- Domain types ---

type Email struct {
	Local  string
	Domain string
}

func (e Email) String() string {
	return e.Local + "@" + e.Domain
}

type Coordinate struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}

// --- Parsing (returns typed value or error) ---

var emailRe = regexp.MustCompile(`^([a-zA-Z0-9._%+\-]+)@([a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})$`)

func ParseEmail(raw string) (Email, error) {
	matches := emailRe.FindStringSubmatch(raw)
	if matches == nil {
		return Email{}, fmt.Errorf("invalid email: %q", raw)
	}
	return Email{Local: matches[1], Domain: matches[2]}, nil
}

func ParseCoordinate(data []byte) (Coordinate, error) {
	var raw struct {
		Lat *float64 `json:"lat"`
		Lon *float64 `json:"lon"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return Coordinate{}, fmt.Errorf("invalid JSON: %w", err)
	}
	if raw.Lat == nil || *raw.Lat < -90 || *raw.Lat > 90 {
		return Coordinate{}, fmt.Errorf("lat must be between -90 and 90")
	}
	if raw.Lon == nil || *raw.Lon < -180 || *raw.Lon > 180 {
		return Coordinate{}, fmt.Errorf("lon must be between -180 and 180")
	}
	return Coordinate{Lat: *raw.Lat, Lon: *raw.Lon}, nil
}

// --- ANTI-PATTERN: Validate, then use raw ---

func IsValidEmail(raw string) bool {
	return emailRe.MatchString(raw) // caller still has untyped string
}

// --- CORRECT: Only accept parsed types ---

func SendWelcome(email Email) string {
	return fmt.Sprintf("Welcome email sent to %s", email)
}
