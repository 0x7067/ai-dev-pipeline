"""Property-based testing with stdlib only (random + unittest)."""
import random
import unittest
from dataclasses import dataclass


@dataclass(frozen=True)
class Money:
    cents: int

    @staticmethod
    def from_dollars(d: float) -> "Money":
        return Money(cents=round(d * 100))

    def to_dollars(self) -> float:
        return self.cents / 100.0

    def add(self, other: "Money") -> "Money":
        return Money(cents=self.cents + other.cents)


def apply_discount(price: Money, pct: int) -> Money:
    if pct < 0 or pct > 100:
        raise ValueError("discount must be 0-100")
    return Money(cents=price.cents * (100 - pct) // 100)


ITERATIONS = 200


class PropertyTests(unittest.TestCase):
    def test_roundtrip_dollars(self):
        """from_dollars → to_dollars preserves value for integer cents."""
        for _ in range(ITERATIONS):
            cents = random.randint(0, 1_000_000)
            m = Money(cents=cents)
            self.assertEqual(Money.from_dollars(m.to_dollars()), m)

    def test_add_commutative(self):
        for _ in range(ITERATIONS):
            a = Money(cents=random.randint(0, 100_000))
            b = Money(cents=random.randint(0, 100_000))
            self.assertEqual(a.add(b), b.add(a))

    def test_discount_bounded(self):
        """Discount result is always between 0 and original price."""
        for _ in range(ITERATIONS):
            price = Money(cents=random.randint(0, 100_000))
            pct = random.randint(0, 100)
            result = apply_discount(price, pct)
            self.assertGreaterEqual(result.cents, 0)
            self.assertLessEqual(result.cents, price.cents)

    def test_discount_idempotent_at_zero(self):
        """0% discount is identity."""
        for _ in range(ITERATIONS):
            price = Money(cents=random.randint(0, 100_000))
            self.assertEqual(apply_discount(price, 0), price)

    def test_discount_monotonic(self):
        """Higher discount percentage → lower or equal result."""
        for _ in range(ITERATIONS):
            price = Money(cents=random.randint(1, 100_000))
            lo = random.randint(0, 99)
            hi = random.randint(lo + 1, 100)
            self.assertGreaterEqual(
                apply_discount(price, lo).cents,
                apply_discount(price, hi).cents,
            )


if __name__ == "__main__":
    unittest.main()
