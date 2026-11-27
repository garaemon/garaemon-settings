---
paths:
  - "**/*.go"
---

# Go Rules

Apply these rules when creating or editing Go code (`*.go`). Go has no sum types and no non-nullable pointers, so these rules use defined types, interfaces, and constructors to keep as many invariants as possible in the type system.

## Data Containers

- Do not return several related values that form one record, such as a width and a height. Define a struct with named fields and return the struct instead.
- Initialize a struct with field names, such as `Size{Width: 3, Height: 4}`. Do not rely on positional struct literals.

The `(value, error)` and `(value, ok)` return pairs are still fine, because they are Go idioms.

BAD:

```go
func ParseSize(text string) (int, int, error) {
	...
}
```

GOOD:

```go
type Size struct {
	Width  int
	Height int
}

func ParseSize(text string) (Size, error) {
	...
}
```

## Defined Types

- Define a named type for a primitive when mixing it up is a bug, such as `type UserID string` versus `type OrderID string`. The compiler then rejects a `UserID` passed where an `OrderID` is expected.
- Use `time.Duration` and `time.Time` instead of a bare integer for a duration or a timestamp.
- When a value has an invariant, keep the fields unexported and expose a constructor that checks the invariant, such as `NewEmail(raw string) (Email, error)`. Code outside the package then cannot build an invalid value.

BAD:

```go
func Transfer(fromAccount int64, toAccount int64, amountCents int64) error
func Wait(timeoutMillis int)
```

GOOD:

```go
type AccountID int64
type Cents int64

func Transfer(fromAccount AccountID, toAccount AccountID, amount Cents) error
func Wait(timeout time.Duration)
```

## Enumerations

- Define a named type and a `const` block with `iota` for a fixed set of values. Do not pass a bare string or integer.
- Start the `iota` block with an explicit invalid or unknown value, so that the zero value never reads as a valid member by accident.
- Run the `exhaustive` linter (for example, through golangci-lint), so that a `switch` that misses a member fails the lint.

```go
type Status int

const (
	StatusUnknown Status = iota
	StatusActive
	StatusInactive
	StatusSuspended
)
```

## Sum Types

Go has no sum type, so emulate one with a sealed interface:

- Define an interface with an unexported marker method, such as `isRequest()`. Only types in the same package can then implement the interface.
- Model each state as its own struct, and do not use one struct whose fields are valid only in some states.
- Handle the states with a type switch, and return an error or panic in the `default` branch, because the compiler does not check exhaustiveness. Enable the `exhaustive` or `gochecksumtype` linter to catch a missed state.

BAD:

```go
type Request struct {
	Status string // "loading", "success", or "failure"
	Data   string // Valid only for "success".
	Err    error  // Valid only for "failure".
}
```

GOOD:

```go
type Request interface {
	isRequest()
}

type Loading struct{}
type Success struct{ Data string }
type Failure struct{ Err error }

func (Loading) isRequest() {}
func (Success) isRequest() {}
func (Failure) isRequest() {}

func DescribeRequest(request Request) string {
	switch typedRequest := request.(type) {
	case Loading:
		return "loading"
	case Success:
		return typedRequest.Data
	case Failure:
		return typedRequest.Err.Error()
	default:
		panic(fmt.Sprintf("unknown request: %T", request))
	}
}
```

## Avoiding any

Avoid `any` (`interface{}`) and `map[string]any` wherever you can. The compiler stops checking a value typed as `any`, so a mistake surfaces only at runtime as a failed type assertion.

Use these alternatives instead:

- Use a concrete type, or a small interface that lists only the methods the code needs.
- Use generics with a type constraint when the output type follows the input type.
- Unmarshal JSON or YAML into a struct with field tags at the boundary where the data enters the program. Do not pass `map[string]any` around.
- Use the two-value form `value, ok := x.(T)` for every type assertion. Never use the single-value form, which panics on a mismatch.

`any` is still fine when an external API requires it, such as `fmt.Printf` or `json.Marshal`.

## Pointers and Absence

- Do not use a pointer only to express that a value may be absent. Every pointer can be `nil`, and the compiler does not force the caller to check it.
- Return `(value, error)` when absence is an error, and `(value, bool)` when absence is an expected result, such as a cache lookup.
- Use a pointer field in a struct only when the code needs to tell "unset" from the zero value, such as an optional field in a JSON payload, and narrow it right after unmarshaling.
- Do not use the `unsafe` package or `reflect` to bypass the type system unless no typed alternative exists. Explain the reason in a comment.
