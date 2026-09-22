# React

> Scope: React 19+ application patterns — Server Components, hooks discipline, state ownership, data fetching, forms, performance, and testing with Vitest and Testing Library.

Version floors (verify upstream; treat as minimums):

| Feature | Availability | Notes |
| --- | --- | --- |
| React 19 | stable line since late 2024 | `use`, actions, ref-as-prop, metadata |
| `useActionState`, `useOptimistic`, `useFormStatus` | React 19 | form-centric APIs |
| `useEffectEvent` | React 19.x | stable on current minors; verify |
| `<Activity>` | React 19.x | pre-render/hide trees; verify |
| React Compiler | 1.0 in 2025 | opt-in build plugin; verify maturity |
| Server Components | framework-driven (Next.js, Remix/RR7, etc.) | not standalone React DOM |
| Testing Library + Vitest | current | `@testing-library/react` v16+ |

Treat "React 20" rumors as unconfirmed until released; pin the 19 line and verify upstream before adopting a new major.

## 1. React 19 baseline

What changed that matters for new code:

- Refs are regular props for function components; `forwardRef` is no longer needed.
- `PropTypes` and string refs were removed; legacy class lifecycles are discourage-only.
- Actions unify mutations: async functions passed to `<form action>` or `startTransition`, with `useActionState` for result state and `useFormStatus`/`useOptimistic` for pending UI.
- `use()` reads promises and context; Suspense boundary placement decides UX.
- Document metadata (`<title>`, `<meta>`, `<link>`) can be rendered in components.
- `ref` cleanup functions are supported; returning a function from `ref` is the new cleanup contract.

## 2. Server Components and the client boundary

The server/client split is a build-time distinction, not a runtime one.

```tsx
// app/users/[id]/page.tsx — Server Component by default (no directive)
import { db } from "@/server/db";
import { LikeButton } from "./like-button";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;              // Next.js 15-era async params
  const user = await db.user.findUniqueOrThrow({ where: { id } });
  return <main><h1>{user.name}</h1><LikeButton userId={user.id} /></main>;
}
```

```tsx
"use client"; // marks this file and its imports as client-side
import { useOptimistic, useTransition } from "react";

export function LikeButton({ userId }: { userId: string }) {
  const [pending, startTransition] = useTransition();
  const [likes, addLike] = useOptimistic(0, (n: number) => n + 1);
  return (
    <button disabled={pending} onClick={() => startTransition(() => addLike(0))}>
      Like ({likes})
    </button>
  );
}
```

Rules:

| Rule | Reason |
| --- | --- |
| `"use client"` at the top of the boundary file | everything it imports becomes client code |
| Server-to-client props must be serializable | functions (except Server Actions), classes, symbols fail |
| Client components cannot import server-only modules | use a server action or route handler instead |
| `server-only` package for DB/secret modules | build-time error instead of leaked secret |
| Do not pass `Date`/Map/Set across the boundary without a wire format | serialization rules are strict |
| Server Actions are public HTTP endpoints | authenticate and validate inside every action |

Server Actions:

```tsx
"use server";
import { z } from "zod";
import { auth } from "@/server/auth";

const Input = z.object({ title: z.string().min(1).max(200) });

export async function createPost(formData: FormData) {
  const session = await auth();                      // authorize first
  if (!session) throw new Error("unauthorized");
  const input = Input.parse(Object.fromEntries(formData)); // validate second
  await db.post.create({ data: { ...input, userId: session.userId } });
  revalidatePath("/posts");
}
```

## 3. Hooks discipline

Rules of hooks are non-negotiable; ESLint's `react-hooks` rules are the enforcement. Beyond that, the senior decisions:

| Hook | Use for | Do not use for |
| --- | --- | --- |
| `useState` | independent local UI state | derived values, server data |
| `useReducer` | multi-field state with transitions | two booleans that form a union |
| `useRef` | DOM handles, mutable instance values | triggering renders |
| `useEffect` | synchronizing with external systems (subscriptions, imperative APIs) | data fetching, derived state, event logic |
| `useLayoutEffect` | measure-before-paint | anything that can run post-paint |
| `useEffectEvent` | stable callback reading latest props/state inside an effect | replacing the dependency array |
| `useMemo`/`useCallback` | proven hot paths or stable identities for memo children | everything "just in case" |
| `useTransition` | non-urgent state updates, pending UX | server mutations without local state |
| `useDeferredValue` | expensive derived renders on input | network debouncing |
| `useSyncExternalStore` | external stores, SSR-safe subscriptions | plain state |

Effect discipline: an effect either subscribes to something outside React or synchronizes to a browser API. If it computes UI from props, the state is derived — compute it in render instead.

```tsx
function Search({ items, query }: { items: Item[]; query: string }) {
  const filtered = items.filter((i) => i.name.includes(query)); // derived in render
  return <List items={filtered} />;
}
```

## 4. State ownership decision

| State kind | Owner | Tooling |
| --- | --- | --- |
| One component's UI state | component | `useState`/`useReducer` |
| Shared by a subtree | nearest common parent or context | props first, then context |
| Server data cache | query library | TanStack Query |
| Cross-cutting client state | external store | Zustand, Jotai, Redux Toolkit |
| URL-addressable state | the URL | `searchParams`, router state |
| Form state | the form library | react-hook-form or native form actions |

Rules: do not mirror server data into Zustand; do not put state in context that changes once per keystroke; derive everything derivable.

Zustand 5 sketch:

```ts
import { create } from "zustand";
import { persist } from "zustand/middleware";

type CartState = {
  items: Record<string, number>;
  add: (sku: string) => void;
  clear: () => void;
};

export const useCart = create<CartState>()(
  persist(
    (set) => ({
      items: {},
      add: (sku) => set((s) => ({ items: { ...s.items, [sku]: (s.items[sku] ?? 0) + 1 } })),
      clear: () => set({ items: {} }),
    }),
    { name: "cart" },
  ),
);
```

Always select narrowly: `useCart((s) => s.items[sku])`, never `useCart()` for the whole object in hot components.

## 5. Data fetching: TanStack Query v5 patterns

```tsx
import { queryOptions, useQuery, useMutation, useQueryClient } from "@tanstack/react-query";

export const userQueries = {
  detail: (id: string) =>
    queryOptions({
      queryKey: ["user", id] as const,
      queryFn: ({ signal }) => fetch(`/api/users/${id}`, { signal }).then((r) => r.json()),
      staleTime: 30_000,
    }),
};

function UserCard({ id }: { id: string }) {
  const { data, isPending, error } = useQuery(userQueries.detail(id));
  if (isPending) return <Skeleton />;
  if (error) return <ErrorBox error={error} />;
  return <div>{data.name}</div>;
}
```

Practices:

- Query keys are tuples: `[entity, ...identifiers, params]`; centralize factories per entity.
- `staleTime` is the cache policy; `gcTime` is memory retention. Defaults are conservative — set them deliberately.
- Mutations own invalidation: `onSuccess` invalidates affected keys or sets exact data.
- `useSuspenseQuery` when the framework has Suspense boundaries; pair with error boundaries.
- Prefetch on hover/route via `ensureQueryData` in loaders.
- For RSC apps, read server-side with the same query client and hydrate; do not double-fetch.

## 6. Forms

Two supported styles; pick per surface.

Native actions + server validation:

```tsx
"use client";
import { useActionState } from "react";

export function LoginForm({ action }: { action: (state: string | null, fd: FormData) => Promise<string | null> }) {
  const [error, formAction, pending] = useActionState(action, null);
  return (
    <form action={formAction}>
      <input name="email" type="email" required />
      <input name="password" type="password" required />
      <button disabled={pending}>Sign in</button>
      {error && <p role="alert">{error}</p>}
    </form>
  );
}
```

Client-heavy forms with react-hook-form + zod:

```tsx
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";

const Schema = z.object({
  email: z.string().email(),
  age: z.coerce.number().int().min(18),
});
type FormValues = z.infer<typeof Schema>;

export function ProfileForm() {
  const { register, handleSubmit, formState } = useForm<FormValues>({
    resolver: zodResolver(Schema),
    defaultValues: { email: "", age: 18 },
  });
  return (
    <form onSubmit={handleSubmit((values) => save(values))}>
      <input {...register("email")} />
      <input type="number" {...register("age")} />
      <button disabled={formState.isSubmitting}>Save</button>
    </form>
  );
}
```

Rules: validate on both sides; server validation is authoritative (see [06-backend-node](./06-backend-node.md)); disable submit while pending; show field errors in `aria-live` regions; never trust `FormData` shapes.

## 7. Performance

Order of interventions, cheapest first:

1. Fix data waterfalls (parallel fetches, RSC streaming, loader prefetch).
2. Reduce client boundary size (`"use client"` as low as possible).
3. Split bundles with dynamic `import()` and route-level code splitting.
4. Memoize identity only where a memo child or effect dependency requires it.
5. Enable React Compiler where the toolchain is stable; verify output and bundle impact.
6. Virtualize long lists; avoid layout thrash in effects.
7. Measure: React DevTools Profiler, `<Profiler>`, Core Web Vitals field data.

React Compiler notes: it eliminates most manual `memo`/`useMemo` when code follows the rules of hooks and has no mutation escapes. If the compiler is enabled, stop sprinkling manual memoization — mixed strategies confuse readers and can regress. Verify plugin maturity and build times upstream.

Common regressions: inline object/array props into memoized children, context value recreated every render, `key={index}` on reorderable lists, fetching in `useEffect` (waterfalls), and derived state stored in `useState` synced by effects.

## 8. Testing React with Vitest and Testing Library

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, test, vi } from "vitest";

test("submits the form", async () => {
  const onSubmit = vi.fn().mockResolvedValue(undefined);
  render(<ProfileForm onSubmit={onSubmit} />);
  await userEvent.type(screen.getByLabelText(/email/i), "a@b.co");
  await userEvent.click(screen.getByRole("button", { name: /save/i }));
  expect(onSubmit).toHaveBeenCalledWith({ email: "a@b.co", age: 18 });
});
```

Practices:

- Query by role, label, or text; `testid` is a last resort.
- Use `userEvent`, not `fireEvent`, for interaction realism.
- Wrap network with MSW; assert on UI, not implementation details.
- Prefer one integration-level render per behavior over mocked children.
- Test error and pending states explicitly.
- For RSC, test server components as functions returning elements and cover client components separately; end-to-end behavior belongs to Playwright.

Full strategy: [07-testing](./07-testing.md).

## Anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| Fetching in `useEffect` | waterfalls, race conditions | query library or RSC/loader |
| Derived state in `useState` + effect | stale flashes | compute in render |
| `"use client"` at the app root | whole app client-bundled | push boundary down |
| Context for fast-changing values | every consumer re-renders | store with selectors or lifted state |
| Prop drilling through RSC boundaries | non-serializable props | server action or client store |
| `useMemo` everywhere | noise, no measurable gain | profile first |
| `key={index}` on dynamic lists | wrong reconciliation | stable ids |

## Checklist

- [ ] Server/client boundary explicit and as deep as possible.
- [ ] No secrets or DB imports reachable from client files (`server-only` enforced).
- [ ] Server Actions authenticate, validate, and authorize independently.
- [ ] Effects only synchronize with external systems; data fetching delegated.
- [ ] State owned at the right level; server cache not duplicated in client stores.
- [ ] Forms validate on client and server with one shared schema.
- [ ] Performance work driven by a profile, not by habit.
- [ ] Tests query by role/label and cover pending, error, and empty states.

Related: [04-frameworks](./04-frameworks.md) for framework integration, [06-backend-node](./06-backend-node.md) for action/route validation, [07-testing](./07-testing.md) for the full test stack.
