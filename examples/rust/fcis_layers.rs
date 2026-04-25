//! FC/IS layers: pure core, boundary parser, and shell orchestrator.
#![allow(dead_code)]

use std::collections::HashMap;

// --- Domain types ---

#[derive(Debug, Clone, PartialEq)]
struct Order {
    product: String,
    quantity: u32,
    unit_price: f64,
}

// --- Core (pure, no I/O) ---

fn calculate_total(order: &Order, tax_rate: f64) -> f64 {
    let subtotal = order.quantity as f64 * order.unit_price;
    subtotal * (1.0 + tax_rate)
}

// --- Boundary (parse raw data into domain types) ---

#[derive(Debug)]
struct ParseError {
    field: String,
    message: String,
}

fn parse_order(raw: &HashMap<String, String>) -> Result<Order, ParseError> {
    let product = raw
        .get("product")
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(|| ParseError {
            field: "product".into(),
            message: "required non-empty string".into(),
        })?
        .trim()
        .to_string();

    let quantity: u32 = raw
        .get("quantity")
        .ok_or_else(|| ParseError {
            field: "quantity".into(),
            message: "required".into(),
        })?
        .parse()
        .map_err(|_| ParseError {
            field: "quantity".into(),
            message: "must be a positive integer".into(),
        })?;

    if quantity < 1 {
        return Err(ParseError {
            field: "quantity".into(),
            message: "must be at least 1".into(),
        });
    }

    let unit_price: f64 = raw
        .get("unit_price")
        .ok_or_else(|| ParseError {
            field: "unit_price".into(),
            message: "required".into(),
        })?
        .parse()
        .map_err(|_| ParseError {
            field: "unit_price".into(),
            message: "must be a number".into(),
        })?;

    if unit_price < 0.0 {
        return Err(ParseError {
            field: "unit_price".into(),
            message: "must be non-negative".into(),
        });
    }

    Ok(Order {
        product,
        quantity,
        unit_price,
    })
}

// --- Shell (I/O, orchestration) ---

fn process_order_from_env() -> Result<String, Box<dyn std::error::Error>> {
    let product = std::env::var("ORDER_PRODUCT")?;
    let quantity = std::env::var("ORDER_QTY")?;
    let price = std::env::var("ORDER_PRICE")?;

    let mut raw = HashMap::new();
    raw.insert("product".into(), product);
    raw.insert("quantity".into(), quantity);
    raw.insert("unit_price".into(), price);

    let order = parse_order(&raw).map_err(|e| format!("{}: {}", e.field, e.message))?;
    let total = calculate_total(&order, 0.1);
    Ok(format!("Order total for {}: ${:.2}", order.product, total))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_total() {
        let order = Order {
            product: "Widget".into(),
            quantity: 3,
            unit_price: 10.0,
        };
        let total = calculate_total(&order, 0.1);
        assert!((total - 33.0).abs() < 0.01);
    }
}
