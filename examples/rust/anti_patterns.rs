//! Anti-patterns vs correct patterns for FC/IS architecture.
#![allow(dead_code)]

use std::collections::HashMap;

// ============================================================
// 1. Raw data in core
// ============================================================

// ANTI-PATTERN: Core function receives raw HashMap
fn calculate_shipping_bad(raw: &HashMap<String, String>) -> f64 {
    let weight: f64 = raw.get("weight").unwrap().parse().unwrap(); // panics!
    if weight < 10.0 { weight * 0.5 } else { weight * 0.3 }
}

// CORRECT: Core function receives parsed domain type
struct ShippingOrder {
    weight_kg: f64,
}

fn calculate_shipping(order: &ShippingOrder) -> f64 {
    if order.weight_kg < 10.0 { order.weight_kg * 0.5 } else { order.weight_kg * 0.3 }
}

// ============================================================
// 2. Validation instead of parsing
// ============================================================

// ANTI-PATTERN: Returns bool, caller still uses raw value
fn is_valid_quantity(q: i32) -> bool {
    q > 0
}

// CORRECT: Returns parsed type or error
struct Quantity(u32);

fn parse_quantity(raw: i32) -> Result<Quantity, String> {
    if raw < 1 {
        return Err(format!("quantity must be positive, got {raw}"));
    }
    Ok(Quantity(raw as u32))
}

// ============================================================
// 3. Panics as flow control
// ============================================================

// ANTI-PATTERN: Using unwrap/panic for expected failure cases
fn parse_config_bad(raw: &str) -> u32 {
    raw.parse().unwrap() // panics on invalid input
}

// CORRECT: Return Result for expected failures
fn parse_config(raw: &str) -> Result<u32, String> {
    raw.parse().map_err(|_| format!("invalid config value: {raw:?}"))
}

// ============================================================
// 4. Mutable global state in core
// ============================================================

// ANTI-PATTERN: Core mutates global state
static mut COUNTER: u64 = 0;

fn next_id_bad() -> u64 {
    unsafe {
        COUNTER += 1;
        COUNTER
    }
}

// CORRECT: Core receives ID as parameter
fn create_with_id(name: &str, id: u64) -> (u64, String) {
    (id, name.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_correct_patterns() {
        assert!((calculate_shipping(&ShippingOrder { weight_kg: 5.0 }) - 2.5).abs() < 0.01);
        assert!(parse_quantity(5).is_ok());
        assert!(parse_quantity(-1).is_err());
        assert!(parse_config("42").is_ok());
        assert!(parse_config("abc").is_err());
    }
}
