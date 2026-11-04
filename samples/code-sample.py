import os
import sys
from dataclasses import dataclass


@dataclass
class Point:
    x: float
    y: float


def distance(a: Point, b: Point) -> float:
    """Return the Euclidean distance between two points."""
    dx = a.x - b.x
    dy = a.y - b.y
    return (dx * dx + dy * dy) ** 0.5


def main(argv: list[str]) -> int:
    origin = Point(0.0, 0.0)
    target = Point(3.0, 4.0)
    print(f"distance = {distance(origin, target)}")
    return 0 if os.path.exists(".") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
