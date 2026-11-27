---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.mts"
  - "**/*.cts"
---

# TypeScript Rules

Apply these rules when creating or editing TypeScript code (`*.ts`, `*.tsx`, `*.mts`, `*.cts`).

## Compiler Settings

- Enable `"strict": true` in `tsconfig.json`.
- Also enable `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, and `noImplicitOverride`. These flags catch an out-of-range index, an explicit `undefined` passed for an optional field, and a silent override.
- Do not loosen these settings to make an error go away. Fix the type instead.

## Type Annotations

- Annotate the parameters and the return type of every exported function.
- Let the compiler infer the type of a local variable when the inferred type is precise.
- Use `readonly` fields and `ReadonlyArray<T>` (or `readonly T[]`) for data that the code does not mutate.
- Use `as const` for a literal object or array that must keep its literal types.

## Avoiding Escape Hatches

Avoid `any`, type assertions (`as`), and the non-null assertion (`!`). Each one tells the compiler to stop checking, so a mistake spreads silently to every place the value reaches.

Use these alternatives instead:

- Use `unknown` for a value of unknown type, and narrow it with a type guard before use.
- Use `satisfies` to check a literal against a type without widening or casting it.
- Use a user-defined type guard (`value is T`) or an assertion function (`asserts value is T`) to narrow a type.
- Parse untyped data, such as `JSON.parse()` output or a `fetch()` response, with a schema library such as zod at the boundary where it enters the program.
- Do not use `@ts-ignore`. Use `@ts-expect-error` with a comment that explains the reason, and only when no typed alternative exists.

`as` is still fine for `as const`, and for a test that builds a partial fake object.

BAD:

```typescript
async function loadUser(url: string): Promise<User> {
  const response = await fetch(url);
  return (await response.json()) as User;
}
```

GOOD:

```typescript
const UserSchema = z.object({
  name: z.string(),
  age: z.number().int(),
});
type User = z.infer<typeof UserSchema>;

async function loadUser(url: string): Promise<User> {
  const response = await fetch(url);
  return UserSchema.parse(await response.json());
}
```

## Data Containers

- Do not use a tuple type, such as `[number, number]`, to bundle related values in a return value or a record.
- Define a named `type` or `interface` with named fields instead.

A tuple is still fine for an API that requires one, such as a React hook that mirrors `useState`.

BAD:

```typescript
function parseSize(text: string): [number, number] {
  const match = /^(\d+)x(\d+)$/.exec(text);
  if (match === null) {
    throw new Error(`invalid size: ${text}`);
  }
  return [Number(match[1]), Number(match[2])];
}
```

GOOD:

```typescript
type Size = {
  readonly width: number;
  readonly height: number;
};

function parseSize(text: string): Size {
  const match = /^(\d+)x(\d+)$/.exec(text);
  if (match === null) {
    throw new Error(`invalid size: ${text}`);
  }
  return { width: Number(match[1]), height: Number(match[2]) };
}
```

## Discriminated Unions

- Model each state as its own object type with a literal `kind` field, and combine the states with `|`.
- Do not use one object type whose optional fields are valid only in some states.
- Check every variant in a `switch`, and assign the value to `never` in the `default` branch. The compiler then reports every variant that a new `switch` misses.

BAD:

```typescript
type Request = {
  status: "loading" | "success" | "failure";
  data?: string;
  error?: Error;
};
```

GOOD:

```typescript
type Request =
  | { readonly kind: "loading" }
  | { readonly kind: "success"; readonly data: string }
  | { readonly kind: "failure"; readonly error: Error };

function describeRequest(request: Request): string {
  switch (request.kind) {
    case "loading":
      return "loading";
    case "success":
      return request.data;
    case "failure":
      return request.error.message;
    default: {
      const unreachable: never = request;
      throw new Error(`unknown request: ${JSON.stringify(unreachable)}`);
    }
  }
}
```

## Enumerations and Branded Types

- Use a union of string literals, such as `"red" | "green"`, for a fixed set of values. Do not use `enum`, because a numeric `enum` accepts any number and an `enum` emits runtime code.
- Use a branded type for a primitive that the code must not mix up, such as a user ID versus an order ID.

```typescript
type UserId = string & { readonly __brand: "UserId" };
type OrderId = string & { readonly __brand: "OrderId" };

function parseUserId(raw: string): UserId {
  if (!/^u_[0-9a-z]+$/.test(raw)) {
    throw new Error(`invalid user ID: ${raw}`);
  }
  // A brand exists only at compile time, so a cast is the only way to attach it.
  return raw as UserId;
}
```

## Null and Undefined

- Avoid optional fields and `T | undefined` return values wherever you can. Return an empty array, throw an error, or use a discriminated union instead.
- Name a function that can return nothing so that the name reveals it, such as `findUser()` rather than `getUser()`.
- Narrow a nullable value as close to its source as possible, so the rest of the code works with the non-nullable type.
