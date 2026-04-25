// Property-based testing using testing/quick.
package examples

import (
	"math"
	"testing"
	"testing/quick"
)

func clampedDiscount(cents int64, pct int) int64 {
	if pct < 0 {
		pct = 0
	}
	if pct > 100 {
		pct = 100
	}
	if cents < 0 {
		cents = 0
	}
	return cents * int64(100-pct) / 100
}

func TestDiscount_Bounded(t *testing.T) {
	f := func(cents int64, pct int) bool {
		if cents < 0 {
			cents = -cents
		}
		result := clampedDiscount(cents, pct)
		return result >= 0 && result <= cents
	}
	if err := quick.Check(f, nil); err != nil {
		t.Error(err)
	}
}

func TestDiscount_ZeroIsIdentity(t *testing.T) {
	f := func(cents int64) bool {
		if cents < 0 {
			cents = -cents
		}
		return clampedDiscount(cents, 0) == cents
	}
	if err := quick.Check(f, nil); err != nil {
		t.Error(err)
	}
}

func TestDiscount_HundredIsZero(t *testing.T) {
	f := func(cents int64) bool {
		if cents < 0 {
			cents = -cents
		}
		return clampedDiscount(cents, 100) == 0
	}
	if err := quick.Check(f, nil); err != nil {
		t.Error(err)
	}
}

func TestDiscount_Monotonic(t *testing.T) {
	f := func(cents int64, lo, hi uint8) bool {
		if cents < 0 {
			cents = -cents
		}
		a, b := int(lo), int(hi)
		if a > b {
			a, b = b, a
		}
		return clampedDiscount(cents, a) >= clampedDiscount(cents, b)
	}
	if err := quick.Check(f, nil); err != nil {
		t.Error(err)
	}
}

func TestRoundTrip_Coordinate(t *testing.T) {
	f := func(lat, lon float64) bool {
		lat = math.Remainder(lat, 90)
		lon = math.Remainder(lon, 180)
		if math.IsNaN(lat) || math.IsNaN(lon) {
			return true
		}
		c := Coordinate{Lat: lat, Lon: lon}
		return c.Lat == lat && c.Lon == lon
	}
	if err := quick.Check(f, nil); err != nil {
		t.Error(err)
	}
}
