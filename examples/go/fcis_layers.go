// FC/IS layers: pure core, boundary parser, and shell orchestrator.
package examples

import (
	"encoding/json"
	"fmt"
	"os"
)

// --- Domain types ---

type Order struct {
	Product   string  `json:"product"`
	Quantity  int     `json:"quantity"`
	UnitPrice float64 `json:"unit_price"`
}

// --- Core (pure, no I/O) ---

func CalculateTotal(order Order, taxRate float64) float64 {
	subtotal := float64(order.Quantity) * order.UnitPrice
	return subtotal * (1 + taxRate)
}

// --- Boundary (parse raw JSON into domain types) ---

type ParseError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

func (e *ParseError) Error() string {
	return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

func ParseOrder(data []byte) (Order, error) {
	var raw struct {
		Product   *string  `json:"product"`
		Quantity  *int     `json:"quantity"`
		UnitPrice *float64 `json:"unit_price"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return Order{}, &ParseError{Field: "body", Message: "invalid JSON"}
	}
	if raw.Product == nil || *raw.Product == "" {
		return Order{}, &ParseError{Field: "product", Message: "required"}
	}
	if raw.Quantity == nil || *raw.Quantity < 1 {
		return Order{}, &ParseError{Field: "quantity", Message: "must be positive"}
	}
	if raw.UnitPrice == nil || *raw.UnitPrice < 0 {
		return Order{}, &ParseError{Field: "unit_price", Message: "must be non-negative"}
	}
	return Order{
		Product:   *raw.Product,
		Quantity:  *raw.Quantity,
		UnitPrice: *raw.UnitPrice,
	}, nil
}

// --- Shell (I/O, orchestration) ---

func ProcessOrderFile(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("reading order file: %w", err)
	}

	order, err := ParseOrder(data)
	if err != nil {
		return "", err
	}

	taxRate := 0.1
	total := CalculateTotal(order, taxRate)
	return fmt.Sprintf("Order total for %s: $%.2f", order.Product, total), nil
}
