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
- Avoid `Any`. See [Avoiding Any](#avoiding-any).

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

## Avoiding Any

Avoid `Any` wherever you can, including inside other types such as `dict[str, Any]`. The type checker skips every value typed as `Any`, so a mistake spreads silently to every place the value reaches.

Use these alternatives instead:

- Use a concrete type or a union of concrete types, such as `int | str`.
- Use `object` when the code accepts any value but never inspects it.
- Use a type variable or a generic class when the output type follows the input type.
- Use a `Protocol` when the code needs only some methods or attributes of a value.
- Parse untyped data, such as JSON or a YAML file, into a dataclass at the boundary where it enters the program. Do not pass `dict[str, Any]` around.
- Use `TypedDict` when a dictionary with fixed keys must stay a dictionary, such as a payload for an external API.

`Any` is still fine in these cases:

- An external library has no type hints, or its types require `Any`.
- A type cannot be expressed in the Python type system.

In those cases, keep `Any` inside the smallest possible scope, and explain the reason in a comment.

BAD:

```python
def load_user(path: str) -> dict[str, Any]:
    with open(path) as user_file:
        return json.load(user_file)


def first_item(items: list[Any]) -> Any:
    return items[0]
```

GOOD:

```python
@dataclass(frozen=True)
class User:
    name: str
    age: int


def load_user(path: str) -> User:
    with open(path) as user_file:
        raw_user = json.load(user_file)
    return User(name=str(raw_user["name"]), age=int(raw_user["age"]))


def first_item[T](items: Sequence[T]) -> T:
    return items[0]
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

## Enumerations

- When a value can take only a fixed set of values, define an `enum.Enum` subclass for the set.
- Do not represent such a value with a bare string or integer constant, such as `"active"` or `1`. A typo in a string literal fails only at runtime, while a typo in an enum member fails at import time and in the type checker.
- Use `enum.StrEnum` or `enum.IntEnum` when the value must interoperate with plain strings or integers, such as a JSON field or a database column.

BAD:

```python
def set_status(status: str) -> None:
    if status not in ("active", "inactive", "suspended"):
        raise ValueError(f"unknown status: {status}")
```

GOOD:

```python
from enum import Enum


class Status(Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    SUSPENDED = "suspended"


def set_status(status: Status) -> None:
    ...
```
