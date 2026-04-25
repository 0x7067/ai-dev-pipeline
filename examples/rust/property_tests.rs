//! Property-based testing with stdlib (manual random generation).
//!
//! For production Rust, use `proptest` crate for property-based testing.
//! This shows the pattern with stdlib only.
#![allow(dead_code)]

fn apply_discount(cents: u64, pct: u8) -> u64 {
    let pct = pct.min(100);
    cents * (100 - pct as u64) / 100
}

fn clamp(value: i64, min: i64, max: i64) -> i64 {
    if value < min {
        min
    } else if value > max {
        max
    } else {
        value
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn simple_rng(seed: u64, count: usize) -> Vec<u64> {
        let mut values = Vec::with_capacity(count);
        let mut state = seed;
        for _ in 0..count {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
            values.push(state >> 33);
        }
        values
    }

    const ITERATIONS: usize = 500;

    #[test]
    fn discount_bounded() {
        for v in simple_rng(42, ITERATIONS * 2).chunks(2) {
            let cents = v[0] % 1_000_000;
            let pct = (v[1] % 101) as u8;
            let result = apply_discount(cents, pct);
            assert!(result <= cents, "discount should not increase price");
        }
    }

    #[test]
    fn discount_zero_is_identity() {
        for cents in simple_rng(123, ITERATIONS) {
            let cents = cents % 1_000_000;
            assert_eq!(apply_discount(cents, 0), cents);
        }
    }

    #[test]
    fn discount_hundred_is_zero() {
        for cents in simple_rng(456, ITERATIONS) {
            let cents = cents % 1_000_000;
            assert_eq!(apply_discount(cents, 100), 0);
        }
    }

    #[test]
    fn discount_monotonic() {
        for v in simple_rng(789, ITERATIONS * 3).chunks(3) {
            let cents = v[0] % 1_000_000;
            let (lo, hi) = if v[1] % 101 <= v[2] % 101 {
                ((v[1] % 101) as u8, (v[2] % 101) as u8)
            } else {
                ((v[2] % 101) as u8, (v[1] % 101) as u8)
            };
            assert!(apply_discount(cents, lo) >= apply_discount(cents, hi));
        }
    }

    #[test]
    fn clamp_idempotent() {
        for v in simple_rng(321, ITERATIONS * 3).chunks(3) {
            let (value, min, max) = (v[0] as i64 % 1000, 0i64, 100i64);
            let once = clamp(value, min, max);
            let twice = clamp(once, min, max);
            assert_eq!(once, twice, "clamp should be idempotent");
        }
    }
}
