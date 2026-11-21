---
paths:
  - "**/*.py"
---

# Python Rules

Apply these rules when creating or editing Python code (`*.py`).

## Type Annotations

- Annotate every parameter and the return value of every function and method. Write `-> None` for a function that returns nothing. Leave `self` and `cls` unannotated.
- Annotate a variable when the type checker cannot infer its type, such as an empty container: `names: list[str] = []`.
- Use built-in generics and the `|` operator: `list[str]`, `dict[str, int]`, `int | str`. Do not use `typing.List`, `typing.Dict`, `typing.Optional`, or `typing.Union`.
- Avoid `Any`. Use a concrete type, a `Protocol`, or a type variable instead. When an external library forces `Any`, explain why in a comment.

BAD:

```python
def count_words(text, ignore_case=False):
    ...
```

GOOD:

```python
def count_words(text: str, ignore_case: bool = False) -> dict[str, int]:
    ...
```

## Avoiding Optional Types

Avoid `X | None` in parameters, return values, and fields wherever you can. Every `None` forces each caller to check for it, and a missed check fails only at runtime.

Use these alternatives instead:

- Raise an exception when a missing value is an error.
- Return an empty collection, such as `[]` or `{}`, instead of `None`.
- Give a parameter a concrete default value. For a sequence, use an immutable default such as `()` instead of `None`.
- Split a function that behaves differently when an argument is `None` into two functions.
- Model each state as its own dataclass, and combine them with `|`, instead of a dataclass whose fields are `None` in some states.

`X | None` is still fine in these cases:

- Absence is an expected result that the caller must handle, such as a cache lookup. Name the function so the name reveals it, such as `find_user()` rather than `get_user()`.
- An external library or API returns or requires `None`.

When a value can be `None`, narrow it to `X` as close to its source as possible, so the rest of the code works with the non-optional type.

BAD:

```python
def load_config(path: str) -> Config | None:
    if not os.path.exists(path):
        return None
    return parse_config(path)


def collect_tags(extra_tags: list[str] | None = None) -> list[str]:
    tags = ["default"]
    if extra_tags is not None:
        tags.extend(extra_tags)
    return tags
```

GOOD:

```python
def load_config(path: str) -> Config:
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    return parse_config(path)


def collect_tags(extra_tags: Sequence[str] = ()) -> list[str]:
    return ["default", *extra_tags]
```

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
