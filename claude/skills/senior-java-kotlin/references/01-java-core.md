# Java Core (21-25)

Scope: modern Java language and runtime features every JVM engineer in this pack is expected to know.

## Release model and floors

| Release | Type | Language highlights |
| --- | --- | --- |
| 21 | LTS | Virtual threads, pattern matching for `switch`, record patterns, sequenced collections |
| 22 | Feature | Unnamed variables, FFM API final, string templates preview (later withdrawn) |
| 23 | Feature | Primitive patterns preview, module imports preview, generational ZGC default |
| 24 | Feature | Synchronized no longer pins virtual threads, security manager permanently disabled |
| 25 | LTS | Scoped values, compact source files/instance `main`, flexible constructor bodies, compact object headers |
| 26+ | Feature | Ship every six months; verify which previews have finalized upstream |

Rules:

- New services target Java 21 at minimum; the current LTS (25) is the default target for production.
- Libraries should compile with `--release 21` even when built on a newer JDK, unless they truly need newer APIs.
- Never depend on a preview feature in production. Preview APIs can change incompatibly between releases and require `--enable-preview` at both compile and run time.
- Keep a JDK matrix in CI: build on the current LTS, test on the next feature release to surface removals early (see `./06-build-tooling.md`).

## Records

Records are transparent, immutable data carriers. Use them for DTOs, events, value objects, query rows, and configuration properties.

```java
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount, "amount");
        Objects.requireNonNull(currency, "currency");
        if (amount.scale() > currency.getDefaultFractionDigits()) {
            throw new IllegalArgumentException("scale exceeds currency precision");
        }
    }

    static Money zero(Currency c) { return new Money(BigDecimal.ZERO, c); }
}
```

Key facts:

- The canonical constructor can be compact (no parameter list) for validation and normalization.
- Records are shallowly immutable: a record holding a `List` still exposes a mutable list. Defensive-copy collections in the compact constructor when the collection is not immutable.
- Records get `equals`, `hashCode`, and `toString`. Do not override them unless there is a strong reason; identity semantics for entities belong on plain classes.
- Records cannot extend a class (they extend `java.lang.Record`) but can implement interfaces and be components of sealed hierarchies.
- Local records are allowed and useful inside methods for intermediate results.
- `record` components are final fields; accessor names are the component names (`amount()`, not `getAmount()`). Serialization bindings may need explicit names.
- Java serialization of records is possible but discouraged; use JSON/Protobuf in services.

Anti-patterns:

- Using records as JPA entities. Hibernate cannot proxy final classes and dirty-checking assumes mutability; use classes for entities (see `./04-persistence.md`).
- Records with many components acting as grab-bag parameter objects; split them.
- Static factories that bypass the canonical constructor with `setAccessible` tricks; validation belongs in the compact constructor.

## Sealed types and algebraic data types

Sealed interfaces/classes restrict who may implement or extend them, enabling exhaustive reasoning.

```java
public sealed interface Payment permits CardPayment, BankTransfer, WalletPayment {}
public record CardPayment(String last4, Instant at) implements Payment {}
public record BankTransfer(String iban, Instant at) implements Payment {}
public record WalletPayment(String walletId, Instant at) implements Payment {}

String label(Payment p) {
    return switch (p) {
        case CardPayment c    -> "card " + c.last4();
        case BankTransfer b   -> "transfer " + b.iban();
        case WalletPayment w  -> "wallet " + w.walletId();
    };
}
```

Notes:

- Permitted subtypes must be in the same module (or same package for the unnamed module); `permits` can be omitted when subtypes are in the same source file.
- Subtypes must be `final`, `sealed`, or `non-sealed`. Marking `non-sealed` reopens the hierarchy and forces default branches again.
- Sealed + records is the idiomatic Java ADT. Combined with pattern matching it replaces visitor-heavy designs.
- Prefer sealed over enums when variants carry different data.

## Pattern matching for switch

Final in Java 21, extended by record patterns.

```java
sealed interface Shape permits Circle, Rect, Group {}
record Circle(double radius) implements Shape {}
record Rect(double w, double h) implements Shape {}
record Group(List<Shape> shapes) implements Shape {}

double area(Shape s) {
    return switch (s) {
        case Circle(double r)          -> Math.PI * r * r;
        case Rect(double w, double h)  -> w * h;
        case Group(List<Shape> shapes) -> shapes.stream().mapToDouble(this::area).sum();
    };
}
```

Rules and gotchas:

- Exhaustiveness is checked for sealed hierarchies; `null` is still a separate case unless explicitly matched (`case null -> ...`).
- Order matters. Put specific cases before broad type patterns; a `case Object o` later makes some later cases unreachable (compile error).
- Guarded patterns via `when` clauses are supported in current JDKs; verify the status of any newer guard syntax in your release.
- Pattern variables are flow-scoped; they are definitely assigned in the matching branch only.
- Boxing of primitive patterns is still evolving as preview; do not build APIs on it yet.

## Virtual threads

Virtual threads are cheap, JVM-scheduled threads designed for blocking I/O. They do not make CPU faster; they remove thread-pool sizing and context-switch costs from blocking workloads.

```java
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    List<Future<Response>> futures = ids.stream()
        .map(id -> executor.submit(() -> client.fetch(id)))
        .toList();
    for (Future<Response> f : futures) {
        results.add(f.get());
    }
}
```

Guidelines:

- Create one virtual thread per task. Do not pool virtual threads; pooling defeats their purpose.
- Use `Thread.ofVirtual().name("fetch-", 0).factory()` when you need naming conventions for diagnostics.
- Blocking JDBC, HTTP, file I/O, and `Thread.sleep` are exactly the workloads virtual threads improve.
- Before JDK 24, `synchronized` blocks pinned the carrier. JDK 24 removes that limitation; on 21-23, replace hot `synchronized` with `ReentrantLock` around blocking calls.
- Native/FFM calls and class initializers can still pin; verify pinning with JFR events (`jdk.VirtualThreadPinned`) on your runtime.
- `ThreadLocal` on a per-task virtual thread is fine but multiplies with thread count; prefer `ScopedValue` (25+) for request context.
- CPU-bound work benefits from platform threads sized to cores; virtual threads add scheduling overhead without parallelism gains.
- Never share a virtual thread's mutable state with other tasks. Each task should own its data.
- Executors created with `newVirtualThreadPerTaskExecutor` are `AutoCloseable`; closing waits for tasks. Prefer structured concurrency when it is available on your release to avoid leaking tasks.

Anti-patterns:

- A fixed virtual-thread pool to "limit concurrency". Use a semaphore or `ScopedValue`-based limiter, or bound the downstream resource instead.
- Using virtual threads to justify synchronous fan-out into an unbounded number of downstream calls; you still need concurrency limits.
- Assuming virtual threads help throughput-bound database work: the database connection pool is the bottleneck, not threads (see `./04-persistence.md`).

## Structured concurrency

Structured concurrency groups related concurrent subtasks so failure, cancellation, and lifetime are handled as a unit. It has been previewed repeatedly; confirm whether it is final in the JDK you target before using it in production.

```java
Response handle(String id) throws Exception {
    try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
        Subtask<User> user = scope.fork(() -> users.find(id));
        Subtask<Orders> orders = scope.fork(() -> orders.forUser(id));
        scope.join().throwIfFailed();
        return new Response(user.get(), orders.get());
    }
}
```

Guidelines while it remains preview:

- The shape is stable enough to design for, but pin the JDK version and accept churn; preview APIs change incompatibly.
- Use `ShutdownOnFailure` for fail-fast fan-out, `ShutdownOnSuccess` for racing equivalent sources with different latencies.
- Always use try-with-resources so the scope is closed and stragglers are cancelled.
- Treat cancellation as expected: subtasks must respond to interruption and clean up.
- Until final, `CompletableFuture` with explicit timeouts plus virtual-thread executors remains the production-safe pattern.

## Scoped values

Scoped values (final in Java 25) carry immutable context to callees without method parameters and without `ThreadLocal` lifetime hazards.

```java
private static final ScopedValue<RequestContext> CONTEXT = ScopedValue.newInstance();

Response handle(Request req) {
    return ScopedValue.where(CONTEXT, RequestContext.from(req))
        .call(() -> service.process(req));
}

RequestContext current() { return CONTEXT.get(); }
```

Rules:

- Scoped values are immutable and visible only inside the dynamic scope of the `where(...).call(...)`; there is no `set`.
- They are inherited by child threads/structured subtasks; this is the intended propagation path for request IDs, tenants, and deadlines.
- Do not use them as hidden mutable state; they are for ambient read-only context.
- Prefer `orElse`/`isBound` when context is optional; throwing `NoSuchElementException` for normal control flow is a smell.
- On JDK 21-24, `ThreadLocal` plus explicit cleanup remains the fallback; document the migration once you move to 25 (see `./10-migration-modernization.md`).

## Sequenced collections

Java 21 added `SequencedCollection`, `SequencedSet`, and `SequencedMap` with uniform first/last/reversed access.

```java
SequencedMap<Instant, String> events = new LinkedHashMap<>();
events.put(t1, "created");
events.put(t2, "updated");
events.putFirst(t0, "draft");

String newest = events.lastEntry().getValue();
SequencedMap<Instant, String> newestFirst = events.reversed();
```

Where it applies:

- `List`, `Deque`, `LinkedHashSet`, `SortedSet`, `LinkedHashMap`, `SortedMap` all expose the sequenced views.
- `Deque` gained `addFirst/addLast`, `getFirst/getLast`, `removeFirst/removeLast` in the sequenced naming; prefer these for intent.
- `Collections.unmodifiableSequencedCollection(...)` and friends preserve sequencing in wrappers.
- Use `getFirst()`/`getLast()` instead of `get(0)`/`get(size()-1)` for clarity and O(1) on deques.

## Compact source files and instance main

Java 25 allows single-file programs without class ceremony, useful for tooling, demos, and small scripts.

```java
void main() {
    IO.println("hello " + (args.length > 0 ? args[0] : "world"));
}
```

- Implicitly declared classes still compile to normal class files; they are syntactic sugar.
- Not for production services: no package declaration, limited module story, tooling assumptions differ.
- Module import declarations (`import module java.base;`) reduce import noise; use sparingly in application code because wildcard module imports hurt readability and can create ambiguity.

## Deprecations, removals, and migration hazards

| Item | Status | Action |
| --- | --- | --- |
| Security manager | Permanently disabled in 24 | Remove `SecurityManager` usage and related flags; use OS sandboxing/modules |
| `sun.misc.Unsafe` memory access | Warned in 23-24, removal planned | Migrate to `VarHandle`, `MethodHandles`, or FFM (`java.lang.foreign`) |
| `finalize()` | Deprecated for removal | Replace with `Cleaner`, try-with-resources, or explicit close |
| `Thread.stop/suspend/resume` | Unsupported operations long-term | Use interruption and cancellation |
| String templates | Withdrawn after preview | Do not design around them; use `String.format`, builders, or templating engines |
| 32-bit x86 port | Removed in 25 | Move to 64-bit; check native dependencies |
| Non-generational ZGC | Removed in 24 | Use `-XX:+UseZGC` generational mode only |
| `javax.*` EE packages | Gone from Jakarta EE 10+ stacks | Migrate to `jakarta.*` (see `./10-migration-modernization.md`) |
| JAXB, JAX-WS, CORBA, Nashorn | Removed from the JDK releases ago | Add explicit dependencies or replace |

Migration practice:

- Run `jdeps --jdk-internals` and `jdeprscan` on every artifact as part of upgrades.
- Compile with `-Xlint:all -Werror` in CI so new deprecation warnings fail the build before they accumulate.
- Use `--add-opens`/`--add-exports` only as a temporary bridge; each one is a tracked task with an owner.
- Test with the strongest encapsulation (`--illegal-access=deny` is the default on modern JDKs) early; reflection failures usually surface at runtime, not compile time.

## Anti-patterns checklist

- [ ] No production dependency on preview features without an explicit, reviewed exception.
- [ ] No `synchronized` around blocking calls on JDK 21-23 virtual-thread paths.
- [ ] No records as JPA entities or as long-lived mutable state.
- [ ] No `ThreadLocal` request context without cleanup and without a documented upgrade path to scoped values.
- [ ] No new use of `Unsafe`, `finalize`, or removed JDK modules.
- [ ] Exhaustive `switch` over sealed types has no unnecessary `default` branch masking new variants.
- [ ] Executors and scopes are closed; nothing leaks tasks past the request boundary.
- [ ] CI compiles with lint warnings as errors and tests on the intended release floor.
