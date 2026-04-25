// Anti-patterns vs correct patterns for FC/IS architecture.
package examples

import (
	"encoding/json"
	"os"
)

// ============================================================
// 1. Raw data in core
// ============================================================

// ANTI-PATTERN: Core function receives raw JSON map
func CalculateShippingBad(raw map[string]interface{}) float64 {
	weight := raw["weight"].(float64) // panics if missing or wrong type
	if weight < 10 {
		return weight * 0.5
	}
	return weight * 0.3
}

// CORRECT: Core function receives parsed domain type
type ShippingOrder struct {
	WeightKg float64
}

func CalculateShipping(order ShippingOrder) float64 {
	if order.WeightKg < 10 {
		return order.WeightKg * 0.5
	}
	return order.WeightKg * 0.3
}

// ============================================================
// 2. Validation instead of parsing
// ============================================================

// ANTI-PATTERN: Returns bool, caller still uses raw value
func IsValidQuantity(q int) bool {
	return q > 0
}

// CORRECT: Returns parsed type or error
type Quantity struct{ Value int }

func ParseQuantity(raw int) (Quantity, error) {
	if raw < 1 {
		return Quantity{}, &ParseError{Field: "quantity", Message: "must be positive"}
	}
	return Quantity{Value: raw}, nil
}

// ============================================================
// 3. I/O in core
// ============================================================

// ANTI-PATTERN: Core reads environment directly
func GetDiscountBad(price float64) float64 {
	rate := os.Getenv("DISCOUNT_RATE") // I/O in core!
	_ = rate
	return price * 0.9
}

// CORRECT: Core receives rate as parameter
func GetDiscount(price float64, discountRate float64) float64 {
	return price * (1 - discountRate)
}

// ============================================================
// 4. Untested boundaries
// ============================================================

// ANTI-PATTERN: No parsing, just unmarshal and hope
func HandleOrderBad(data []byte) float64 {
	var order map[string]interface{}
	json.Unmarshal(data, &order) // error ignored
	return CalculateShippingBad(order)
}

// CORRECT: Parse at boundary, handle errors, pass typed value to core
func HandleOrderCorrect(data []byte) (float64, error) {
	var raw struct {
		WeightKg *float64 `json:"weight_kg"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return 0, err
	}
	if raw.WeightKg == nil || *raw.WeightKg < 0 {
		return 0, &ParseError{Field: "weight_kg", Message: "required non-negative number"}
	}
	return CalculateShipping(ShippingOrder{WeightKg: *raw.WeightKg}), nil
}
