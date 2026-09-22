# Type System, Advanced

> Scope: conditional, mapped, and template-literal types, variance, branding, `satisfies`, `const` type parameters, `infer`, type-level testing, and declaration patterns — with the limits of each.

Version floors (verify upstream; treat as minimums):

| Feature | Introduced | Notes |
| --- | --- | --- |
| `satisfies` | TS 4.9 | annotation checks without widening |
| `const` type parameters | TS 5.0 | preserves literal inference in generics |
| `using` / `Symbol.dispose` | TS 5.2 | needs `lib: esnext.disposable` |
| `NoInfer<T>` | TS 5.4 | stops inference at a position |
| `--isolatedDeclarations` | TS 5.5 | explicit return types for fast DTS |
| Inferred type predicates | TS 5.5 | functions returning boolean can narrow |
| `--erasableSyntaxOnly` | TS 5.8 | rejects enums/namespaces/parameter properties |
| Native compiler (TS 7 line) | announced/preview | same types, Go-based; verify upstream |

## 1. Structural typing, narrowing, and the erasure rule

TypeScript is structural: assignability is about shape, not names. The compiler narrows in `if`, `switch`, `in`, `instanceof`, and via user-defined predicates. None of it survives to runtime.

Rules that prevent most type bugs:

- Every external value starts as `unknown` and is parsed into a type (see [06-backend-node](./06-backend-node.md)).
- Narrow with equality to a literal, `typeof`, `instanceof`, or a predicate — not with `as`.
- Prefer `interface` for public object shapes that may be extended; `type` for unions, mapped/conditional types, and anything needing intersection.
- `readonly` is shallow; deep immutability is a modeled choice, not a modifier.

```ts
function assertNever(value: never): never {
  throw new Error(`Unhandled variant: ${JSON.stringify(value)}`);
}

type Result<T> = { ok: true; value: T } | { ok: false; error: Error };

function unwrap<T>(r: Result<T>): T {
  if (r.ok) return r.value;
  throw r.error;
}
```

## 2. Conditional types

Conditional types select a type from a type. They distribute over naked type parameters, which is the source of both power and surprise.

```ts
type ElementType<T> = T extends readonly (infer U)[] ? U : never;
type Awaited<T> = T extends Promise<infer U> ? Awaited<U> : T;
type IsArray<T> = T extends readonly unknown[] ? true : false;

// Non-distributive: wrap both sides in tuples
type IsNever<T> = [T] extends [never] ? true : false;
type IsUnion<T, U = T> = T extends U ? ([U] extends [T] ? false : true) : never;
```

Distributivity rules:

| Pattern | Behavior |
| --- | --- |
| `T extends U ? X : Y` with naked `T` | distributes over union members |
| `[T] extends [U] ? X : Y` | checks the union as a whole |
| `T & { } extends U` | distributes unless `T` is `never` |
| `any` in the check position | resolves to the union of both branches |

Common built-ins worth knowing instead of reimplementing: `Awaited`, `Exclude`, `Extract`, `NonNullable`, `ReturnType`, `Parameters`, `InstanceType`, `ThisParameterType`, `OmitThisParameter`, `Uppercase` family, `NoInfer`.

Anti-pattern: nested conditionals that return `never` for mismatches. Prefer a small named alias per step and a type test per step (section 9).

## 3. Mapped types

```ts
type DeepReadonly<T> = {
  readonly [K in keyof T]: T[K] extends object ? DeepReadonly<T[K]> : T[K];
};

type Getters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K];
};

type Mutable<T> = { -readonly [K in keyof T]: T[K] };
type RequiredBy<T, K extends keyof T> = Omit<T, K> & { [P in K]-?: T[P] };
```

| Modifier syntax | Effect |
| --- | --- |
| `readonly` / `-readonly` | add / remove readonly |
| `?` / `-?` | add / remove optionality |
| `as` clause | key remapping; `never` drops the key |
| `keyof T` iteration | homomorphic; preserves modifiers |
| `Record<K, V>` | non-homomorphic; does not preserve |

Homomorphic mapped types (`[K in keyof T]`) preserve optionality and `readonly` from `T` and distribute over unions; hand-rolled `Record<string, ...>` does not. Pick intentionally.

## 4. Template literal types

Template literal types model string grammars at compile time. They are erased; runtime validation still owns correctness.

```ts
type Route = `/api/${"users" | "orders"}/${string}`;
type EventName<T extends string> = `on${Capitalize<T>}`;
type Props = { [K in "click" | "focus" as EventName<K>]: (e: Event) => void };

type ParseId<S extends string> =
  S extends `${infer Prefix}_${infer Id}` ? { prefix: Prefix; id: Id } : never;
```

Practical uses: typed event maps, CSS unit strings, dot-paths for i18n keys, SQL table names. For real grammars (paths with parameters, template syntax), reach for a parser (for example a typed router library or Zod) rather than recursive string inference.

Known limits: no arithmetic, no guaranteed normalization, and error messages on failure are long. Depth limits exist for recursive conditional types (the compiler caps instantiation depth; exact cap is version-dependent — verify upstream).

## 5. Variance

TypeScript uses structural subtyping with variance inferred per type parameter; TS 4.7+ allows explicit annotations.

```ts
interface Producer<out T> { get(): T }          // covariant, read-only
interface Consumer<in T> { accept(value: T): void } // contravariant
interface Box<in out T> { get(): T; set(v: T): void } // invariant
```

| Situation | Behavior |
| --- | --- |
| Function parameter with `strictFunctionTypes` | contravariant (correct) |
| Method syntax in an interface | bivariant (escape hatch, historical) |
| Arrays | covariant and unsound |
| Explicit `in` / `out` | checked, faster assignability, clearer errors |

Use `out T` on producers (stores, query results, context values) and `in T` on consumers (handlers, comparators). Do not annotate just to silence errors — if `in`/`out` disagrees, the design is wrong.

## 6. Branded and opaque types

Branded types make identifiers and units distinct at compile time at zero runtime cost.

```ts
declare const brand: unique symbol;
type Brand<T, B extends string> = T & { readonly [brand]: B };

type UserId = Brand<string, "UserId">;
type Email = Brand<string, "Email">;

function userId(raw: string): UserId {
  if (!/^[0-9a-f-]{36}$/.test(raw)) throw new Error("invalid user id");
  return raw as UserId; // one checked cast, at the boundary
}
```

Rules:

- Construct brands only through validating functions; never export the cast.
- Zod/Valibot can produce brands (`z.string().uuid().brand<"UserId">()`), keeping parse and brand unified.
- Keep brands shallow: `Brand<string, "Email">` is enough; branding generics usually bills you in error messages.
- Branded types serialize as their base type; re-parse on the way back in.

## 7. `satisfies` and `const` type parameters

```ts
const routes = {
  home: "/",
  user: (id: string) => `/users/${id}`,
} satisfies Record<string, string | ((id: string) => string)>;

// routes.user stays callable; routes.home stays "/"
const config = { mode: "dark", retries: 3 } as const satisfies Config;
```

| Tool | Effect | Use when |
| --- | --- | --- |
| `:` annotation | widens to the annotated type | you want exactly that API |
| `as const` | literals + readonly, no check | building tuple/literal data |
| `satisfies` | checks without widening | config objects, route maps, theme tokens |
| `as` | unchecked assertion | last resort, never on external data |

`const` type parameters (TS 5.0) apply the same idea inside generics:

```ts
function tuple<const T extends readonly unknown[]>(...items: T): T {
  return items;
}
const t = tuple("a", 1); // readonly ["a", 1]

function defineRoutes<const T extends Record<string, string>>(r: T): T {
  return r;
}
```

## 8. `infer` and controlled recursion

```ts
type UnwrapPromise<T> = T extends Promise<infer U> ? U : T;
type First<T extends readonly unknown[]> = T extends readonly [infer H, ...unknown[]] ? H : never;
type Last<T extends readonly unknown[]> = T extends readonly [...unknown[], infer L] ? L : never;
type Head<T extends string> = T extends `${infer H}${infer _Rest}` ? H : never;
```

Variadic tuple types let signatures capture fragments:

```ts
function curry<A extends unknown[], R>(fn: (...args: A) => R) {
  return (...args: A): R => fn(...args);
}
declare function route<T extends readonly [string, ...unknown[]]>(path: T): T;
```

Type-level tests: `readonly [infer H, ...unknown[]]` requires a tuple; plain arrays return `never` for `First`. Always test both cases. Tail-recursive conditional types are optimized; non-tail recursion hits instantiation limits, so accumulate in an extra type parameter:

```ts
type Reverse<T extends unknown[], Acc extends unknown[] = []> =
  T extends [infer H, ...infer Rest] ? Reverse<Rest, [H, ...Acc]> : Acc;
```

## 9. Type-level testing

Types are code; test them in CI. Three layers:

1. Compile gate — `tsc --noEmit` (or `tsgo --noEmit` for the native compiler) over `src` and `test`.
2. Assertions — `expect-type` or Vitest's `expectTypeOf`, co-located with unit tests.
3. Negative tests — `@ts-expect-error` only where the line genuinely must fail; a bare `// @ts-ignore` is banned by lint.

```ts
import { expectTypeOf, test } from "vitest";

test("UnwrapPromise", () => {
  expectTypeOf<UnwrapPromise<Promise<number>>>().toEqualTypeOf<number>();
});

// Negative assertion: the next line must error, or the test file fails to compile
// @ts-expect-error -- UserId is not a plain string
const bad: UserId = "not-branded";
```

For public libraries, a dedicated `*.test-d.ts` file compiled with `tsc -p tsconfig.test.json` keeps consumer-facing types honest. `tsd` is an alternative but expect-type keeps one runner.

Limits of type tests: they check assignability, not soundness under `any`; they do not test runtime behavior. Pair every type assertion with at least one runtime path if the construct can fail at runtime.

## 10. Declaration patterns

```ts
// env.d.ts — augment a library's types
declare module "some-lib" {
  interface Options { retry?: number }
  export function configure(o: Options): void;
}

// globals.d.ts — augment the global scope
declare global {
  interface Window { __APP_VERSION__: string }
  var __BUILD_ID__: string;
}
export {}; // make this file a module so `declare global` is legal

// module.d.ts — ambient asset modules (Vite can generate these instead)
declare module "*.css" {
  const styles: { [key: string]: string };
  export default styles;
}
```

| Need | Pattern |
| --- | --- |
| Extend a library type | module augmentation in a project `.d.ts` file |
| Add a global | `declare global` inside a module file |
| Type an untyped package | `declare module "pkg"` shim + upstream typings PR |
| Strictly isolate types | `--isolatedDeclarations` plus explicit exported returns |
| Publish `.d.ts` only | `declaration: true` + `emitDeclarationOnly` |

Rules: never patch `node_modules`; keep ambient shims in one `types/` folder; make `skipLibCheck` a conscious tradeoff (it hides broken dependency declarations — see [08-quality-tooling](./08-quality-tooling.md)).

## 11. Type gymnastics: when not to

Compile-time power costs: slower checks, inscrutable errors, and knowledge only one person on the team has. Apply this test before writing >20 lines of type code:

- Does a runtime parser remove the need? (Usually yes at boundaries.)
- Would a small union or a code-generation step be simpler?
- Is the DX win worth the instantiation cost on every build?
- Can it live in a library you publish, not in application code?

If you cannot write a one-line doc comment describing the type, it is probably too clever.

## Anti-patterns

| Anti-pattern | Why it hurts | Instead |
| --- | --- | --- |
| `as unknown as T` | erases evidence | parse and validate |
| Double conditional chains | unreadable errors | named step types + tests |
| Branding every primitive | error-message noise | brand identifiers and units only |
| `enum` for state | runtime object, poor tree-shaking, `erasableSyntaxOnly` conflict | literal union / `as const` |
| `Record<string, any>` | no key checking | `Record<string, unknown>` + parse |
| Recursive types beyond ~50 depth | instantiation explosion | flatten the model |
| Type tests without runtime tests | false confidence | pair both |

## Checklist

- [ ] External values parsed, not cast.
- [ ] `satisfies` used for inferred config objects.
- [ ] Unions discriminated and switched exhaustively with `assertNever`.
- [ ] `in`/`out` variance annotated on generic containers where intent matters.
- [ ] Brands constructed through validators only.
- [ ] Public types covered by `expect-type` tests and a compile gate.
- [ ] No `as` on external data; no `@ts-ignore`; `@ts-expect-error` has a reason.
- [ ] Type-level code under ~20 lines per construct, documented with one line.

Related: [02-modules-build](./02-modules-build.md) for declaration publishing, [06-backend-node](./06-backend-node.md) for runtime validation at service boundaries, [08-quality-tooling](./08-quality-tooling.md) for the compiler flags that make this machinery safe.
