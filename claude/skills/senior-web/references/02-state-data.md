# State and Data

Client state vs server state, forms, URL as state, optimistic UI, and data fetching, caching, and
invalidation patterns across frameworks.

## Classify State Before Choosing a Tool

Most state bugs come from putting the wrong kind of state in the wrong place, not from a bad
library. Classify first:

| Kind | Examples | Right home | Wrong home |
|---|---|---|---|
| Server data | user profile, orders, feed | query library / framework data cache | global store, component state |
| Navigational | tab, filter, page, query | URL search params / route segments | global store |
| Form state | field values, touched, errors | form library / component-local | global store |
| Ephemeral UI | menu open, hover, drag | component state | URL (too noisy), store |
| App-wide client | auth session, theme, locale | small context/store + cookie | server data cache |
| Persisted preference | theme, sidebar collapsed | cookie or `localStorage` | in-memory only |

Rule of thumb: if the server can own it, let the server own it. If the user can bookmark or share
it, put it in the URL. Only truly local, transient UI state belongs in component memory.

## Client State vs Server State

**Client state** is owned by the browser session: modal open, draft text, selected rows before
submit. It is synchronous and cheap.

**Server state** is a cache of data owned elsewhere. It is asynchronous, shared, can be stale, and
can be mutated by others. Treating server data as client state (copying fetched data into a store
and hand-syncing it) is the single most common source of stale-UI bugs.

Use a query library for server state: TanStack Query, SWR, Apollo/urql for GraphQL, or a framework
data cache (RSC fetch cache, SvelteKit load, Nuxt `useFetch`). They provide request deduplication,
staleness tracking, background refetch, and invalidation.

```ts
// TanStack Query: server state with explicit staleness and invalidation
const { data, isPending } = useQuery({
  queryKey: ["orders", { status }],
  queryFn: () => api.orders({ status }),
  staleTime: 30_000,
});

const mutation = useMutation({
  mutationFn: api.cancelOrder,
  onSuccess: () => queryClient.invalidateQueries({ queryKey: ["orders"] }),
});
```

For global client state keep it small: Zustand, Jotai, Pinia, or framework context. Do not put
server data there. If a store holds "the current user" for UI decisions, derive it from the
server-state cache rather than duplicating it.

## URL as State

The URL is the only state store with built-in back/forward, sharing, and deep-linking. Put in it:

- filters, sort order, pagination, search query
- active tab/section when the user may return to it
- selected entity IDs when the selection is meaningful to share
- multi-step form progress when steps are navigable

```ts
// Next.js: typed URL state with native history integration
const searchParams = useSearchParams();
const page = Number(searchParams.get("page") ?? "1");
router.replace(`?${new URLSearchParams({ ...params, page: String(page + 1) })}`);
```

Guidelines:
- Use `replace` for high-frequency updates (typing in a search box), `push` for discrete navigation.
- Debounce writes to the URL for text input; keep input value in local state while typing.
- Parse params defensively: unknown values must fall back, never crash.
- Prefer search params over path segments for orthogonal filters; use path segments for identity.

## Forms

Forms are the highest-risk interface: they combine user input, validation, network mutation, and
error recovery. The 2026 default is server-first forms with progressive enhancement.

### Server-first pattern

- Submit to a server endpoint that validates and mutates.
- Return structured field errors; map them to inputs and focus the first invalid field.
- Keep working when JS fails: native `<form method="post" action="/endpoint">` is the baseline.
- Use framework server actions where available (React/Next server actions, SvelteKit form actions,
  Nuxt server routes) for type-safe round trips without hand-written API clients.

```tsx
// React server action: no client fetch, works before hydration
async function updateEmail(formData: FormData) {
  "use server";
  const parsed = Schema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return { errors: parsed.error.flatten().fieldErrors };
  await db.user.update({ data: parsed.data });
  redirect("/settings");
}
```

### Validation rules

- Validate on the server always; validate on the client only for fast feedback.
- Reuse one schema (Zod/Valibot/etc.) on both sides to prevent drift.
- Validate on blur or submit, not on every keystroke; do not shame the user mid-typing.
- Success message must be announced to assistive tech (`role="status"`), errors linked with
  `aria-describedby` and `aria-invalid` — see [05-accessibility.md](./05-accessibility.md).
- Disable double-submit via pending state, not by disabling the button before validation runs.

### Multi-step forms

Keep draft state client-side or in a server session; keep step number in the URL. Persist drafts
when the form is long (`localStorage` as best-effort, server draft as source of truth). Never lose
user input on refresh.

## Optimistic UI

Optimistic updates render the expected result before the server confirms, then reconcile or roll
back. They dramatically improve perceived speed on slow networks; they also can lie to users.

Use when: the action almost always succeeds, the result is predictable, and the user can tolerate a
rare correction (likes, toggles, renames, sending a message).

Avoid when: money, destructive actions, irreversible state, or results whose shape depends on the
server (generated IDs, computed totals, conflict resolution).

```ts
const mutation = useMutation({
  mutationFn: api.toggleLike,
  onMutate: async ({ id }) => {
    await queryClient.cancelQueries({ queryKey: ["post", id] });
    const previous = queryClient.getQueryData(["post", id]);
    queryClient.setQueryData(["post", id], (old) => ({ ...old, liked: !old.liked }));
    return { previous }; // context for rollback
  },
  onError: (_err, { id }, context) => {
    queryClient.setQueryData(["post", id], context.previous);
    toast.error("Could not update. Try again.");
  },
  onSettled: (_data, _err, { id }) => queryClient.invalidateQueries({ queryKey: ["post", id] }),
});
```

Rules: always implement rollback and an error surface; keep an `onSettled` refetch to converge with
the server; never optimistically invent server-authored data (IDs, timestamps, prices).

## Data Fetching Patterns

### Server render / RSC

Fetch on the server, pass plain data down. Eliminates request waterfalls visible to users, removes
secrets from the client, and reduces bundle size. Parallelize independent fetches:

```ts
const [user, orders, flags] = await Promise.all([getUser(id), getOrders(id), getFlags(id)]);
```

### Client fetching

Use for user-triggered, live, or highly interactive data. Prefer route loaders / `useQuery`-style
hooks over `useEffect` + `fetch`. Avoid fetch-in-effect unless the request is truly imperative:
it races, cannot dedupe by default, and has no retry or cache story.

### Pagination and infinite lists

| Pattern | Use when | Notes |
|---|---|---|
| Offset/limit | Small, jump-to-page UIs | Degrades on deep pages; may duplicate rows on writes |
| Cursor | Feeds, large data | Stable under writes; no page numbers |
| Infinite scroll | Social/feed UX | Provide "load more" fallback and restore scroll on back |
| Virtualized list | 1k+ rendered rows | Render window only; keep totals for a11y |

Always reflect page/cursor state in the URL for shareability, per the URL-as-state rule.

### Real-time

- **WebSocket** for bidirectional, high-frequency (collab, chat). Reconnect with backoff; resume
  from a cursor to avoid missed messages.
- **SSE** for server-to-client streams (feeds, progress); simpler, works over HTTP/2.
- **Polling** as last resort or fallback; make interval adaptive (fast when visible, stop when
  hidden).
- Realtime updates should write into the same server-state cache, not a parallel store.

## Caching and Invalidation

A cache entry needs three decisions: key, lifetime, and invalidation trigger.

- **Keys** must include everything that changes the response: query args, user scope, locale.
  `["orders", { status, page }]` not `["orders"]`.
- **Staleness** (`staleTime`) is how long data is trusted; `gcTime`/`cacheTime` is how long unused
  data is retained. Tune per resource: profile (minutes), price (seconds), static lookup (hours).
- **Refetch triggers** — on mount, on window focus, on reconnect. Enable the ones that match the
  resource; disable for expensive endpoints.
- **Invalidation** — after mutation, invalidate the narrowest key prefix that covers changed data.
  Broad invalidation is a correctness fix with a performance cost; narrow is a performance win with
  a correctness risk. Test both.

For HTTP/CDN and framework invalidation, see
[01-architecture-rendering.md](./01-architecture-rendering.md).

## State Anti-Patterns

- Copying server responses into a global store and syncing by hand.
- Two sources of truth for the same value (URL page and component page state).
- Fetching in `useEffect` with no abort, dedupe, or error boundary.
- Putting every toggle in a global store; global state should be rare.
- Deriving state in render that could be computed from props/URL (redundant state).
- Blocking the whole page on one slow query instead of streaming or splitting.
- Forgetting the loading and empty states; every async view needs pending, error, empty, and
  populated designs.

## Checklist

- [ ] State classified (server / URL / form / UI) and placed accordingly.
- [ ] Query keys include all response-affecting inputs; invalidation tested after mutations.
- [ ] Forms validate server-side, work without JS, and announce errors.
- [ ] Optimistic paths have rollback plus a refetch to converge.
- [ ] Back/forward and refresh reproduce the view.
- [ ] Loading, error, and empty states designed for every async surface.
