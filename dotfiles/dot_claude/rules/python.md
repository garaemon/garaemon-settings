---
paths:
  - "**/*.py"
---

# Python Rules

Apply these rules when creating or editing Python code (`*.py`).

## Data Containers

- Do not use a tuple to bundle related values, such as a multi-value return or a record.
- Define a dataclass with `@dataclass(frozen=True)` instead, so every field has a name and a type.
- Do not use `collections.namedtuple` or `typing.NamedTuple` either. They still behave as tuples, so callers can unpack or index them by position.
- Use `dataclasses.replace()` to derive a modified copy instead of mutating a field.

A tuple is still fine in these cases:

- A homogeneous, immutable sequence, such as `tuple[str, ...]`.
- An API that requires a tuple, such as `isinstance()` or a dictionary key.

BAD:

```python
def parse_size(text: str) -> tuple[int, int]:
    width, height = text.split("x")
    return int(width), int(height)
```

GOOD:

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class Size:
    width: int
    height: int


def parse_size(text: str) -> Size:
    width, height = text.split("x")
    return Size(width=int(width), height=int(height))
```
