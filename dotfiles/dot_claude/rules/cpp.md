---
paths:
  - "**/*.cpp"
  - "**/*.cc"
  - "**/*.cxx"
  - "**/*.hpp"
  - "**/*.hh"
  - "**/*.hxx"
  - "**/*.h"
---

# C++ Rules

Apply these rules when creating or editing C++ code (`*.cpp`, `*.cc`, `*.cxx`, `*.hpp`, `*.hh`, `*.hxx`, and C++ `*.h` headers). Use the C++ standard that the project sets, and prefer C++17 or later features where the project allows them.

## Data Containers

- Do not use `std::pair` or `std::tuple` to bundle related values in a return value or a record. `first`, `second`, and `std::get<1>` name nothing.
- Define a `struct` with named fields instead, and initialize it with designated initializers in C++20 or later.

`std::pair` and `std::tuple` are still fine for an API that requires one, such as `std::map::insert()` or generic code.

BAD:

```cpp
std::pair<int, int> ParseSize(std::string_view text);
```

GOOD:

```cpp
struct Size {
  int width;
  int height;
};

Size ParseSize(std::string_view text);
```

## Strong Types

- Wrap a primitive in its own type when mixing it up is a bug, such as a user ID versus an order ID, or meters versus seconds.
- Mark single-argument constructors `explicit`, so that the compiler never converts a raw value silently.
- Use `std::chrono` types for durations and time points instead of a bare integer.

BAD:

```cpp
void Transfer(int64_t from_account, int64_t to_account, int64_t amount_cents);
void Sleep(int timeout);
```

GOOD:

```cpp
class AccountId {
 public:
  explicit AccountId(int64_t value) : value_(value) {}
  int64_t value() const { return value_; }

 private:
  int64_t value_;
};

struct Cents {
  int64_t value;
};

void Transfer(AccountId from_account, AccountId to_account, Cents amount);
void Sleep(std::chrono::milliseconds timeout);
```

## Enumerations

- Use `enum class` for a fixed set of values. Do not use a plain `enum` or integer constants, because both convert to and from `int` silently.
- Do not add a `default` label to a `switch` over an `enum class`. Enable `-Wswitch` (or `-Wswitch-enum`), so that the compiler reports every value that a `switch` misses.

## Sum Types

- Model each state as its own `struct`, and combine the states with `std::variant`.
- Do not use one `struct` whose fields are valid only in some states, or a `struct` with a type tag and a `union`.
- Visit a `std::variant` with `std::visit` and an overload set, so that the compiler rejects a visitor that misses an alternative.

BAD:

```cpp
struct Request {
  enum Status { kLoading, kSuccess, kFailure } status;
  std::string data;   // Valid only for kSuccess.
  std::string error;  // Valid only for kFailure.
};
```

GOOD:

```cpp
struct Loading {};
struct Success {
  std::string data;
};
struct Failure {
  std::string error;
};
using Request = std::variant<Loading, Success, Failure>;

template <class... Visitors>
struct Overloaded : Visitors... {
  using Visitors::operator()...;
};
// C++17 needs this deduction guide. C++20 deduces the type without it.
template <class... Visitors>
Overloaded(Visitors...) -> Overloaded<Visitors...>;

std::string DescribeRequest(const Request& request) {
  return std::visit(
      Overloaded{
          [](const Loading&) { return std::string("loading"); },
          [](const Success& success) { return success.data; },
          [](const Failure& failure) { return failure.error; },
      },
      request);
}
```

## Absence and Errors

- Use `std::optional<T>` for a value that may be absent. Do not use a sentinel value, such as `-1` or an empty string, or a nullable raw pointer.
- Use `std::expected<T, E>` (C++23) or the project's result type for an operation that can fail with a reason. Do not return an error code through an output parameter.
- Avoid optional values where you can, as the type-driven rules in `CLAUDE.md` describe. Narrow a `std::optional` as close to its source as possible.

## Ownership and Escape Hatches

- Express ownership in the type. Use `std::unique_ptr` for sole ownership, `std::shared_ptr` only for shared ownership, and a reference or a raw pointer only for a non-owning view.
- Use `std::span` and `std::string_view` to pass a view of contiguous data, instead of a pointer and a length.
- Do not use `void*`, `std::any`, C-style casts, or `reinterpret_cast`. Use templates or `std::variant` instead.
- Use `static_cast` only for a conversion that the type system cannot express, and keep it at the boundary.
- Use concepts (C++20) or `static_assert` to state the requirements of a template parameter.
