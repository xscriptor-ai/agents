# Data, Offline, and Sync

Local storage choices, sync engine options, outbox and conflict resolution patterns, background
sync constraints, and offline-first UX for mobile clients.

## Offline Is the Default State

Mobile networks fail, processes are killed, and users expect the app to keep working. Model the
client as a local database that happens to replicate with a server:

- Reads resolve from the local store first, then reconcile.
- Writes commit locally, enter an outbox, and sync when possible.
- Every entity has a stable client-generated ID (UUID/ULID) so records can be created offline.
- Every row carries sync metadata: `updated_at`, `revision`/version, `deleted_at` (tombstone), and
  an origin marker to suppress echo.

The alternative — network-first with a cache — produces blank screens on a train and lost writes on
a crash. Avoid it for any app whose data matters.

## Local Storage Choices

| Store | Model | Strengths | Watch out for |
|---|---|---|---|
| SQLite (Room, GRDB, Drift, SQLDelight) | Relational | Queries, transactions, migrations, mature | Schema migration and thread discipline are on you |
| Key-value (MMKV, DataStore, UserDefaults) | KV | Fast, tiny surface | Not queryable; never for tokens |
| Files + index | Blobs | Media, documents, large payloads | Keep out of DB; manage eviction and backup |
| Document stores (Couchbase Lite) | JSON docs | Built-in replication, conflict handling | Heavier footprint; query model differs |
| Sync engines (PowerSync, Electric, Firestore) | Managed | Handles replication, auth, and often conflicts | Vendor coupling, cost, sync semantics to learn |

Decision guide:

- Small datasets, simple queries, existing SQL skills: SQLite.
- Blobs and media: file storage with a metadata table.
- Apps that are fundamentally about syncing shared documents: prefer a sync engine or a document
  database over hand-rolled replication.
- Never store credentials in a KV store; see [./08-security.md](./08-security.md).

Note on deprecated options: MongoDB's Realm/Atlas Device SDK line has been deprecated; do not start
new projects on it, and plan migration for existing ones. Verify the current status of any
managed backend upstream before adoption.

## Sync Engine Landscape

| Engine | Model | Best for |
|---|---|---|
| PowerSync | SQLite replica + server connector | Existing Postgres/MySQL backends, teams wanting SQL locally |
| ElectricSQL | Postgres shapes to local SQLite | Read-heavy Postgres apps, incremental sync |
| Couchbase Lite | Document DB with replication | Multi-master document data, Couchbase Server |
| Firestore | Cloud document store with offline cache | Firebase-native apps; conflicts are last-write-wins |
| Supabase Realtime + local cache | Postgres + realtime | Supabase apps willing to own reconciliation |
| Custom (delta API + outbox) | Full control | Unusual auth or compliance constraints |

Buying sync is usually cheaper than building it. Build custom only when no engine fits the data
model or compliance boundary, and budget for the hard parts: conflict policy, schema evolution,
tombstones, and per-account encryption.

## Outbox Pattern

A write path that survives offline:

1. User action creates a local record with a client ID and `pending` status.
2. An outbox row records the intended mutation (entity, operation, payload, timestamp, retry count).
3. A sync worker drains the outbox in order, applying server acknowledgment or conflict resolution.
4. On success, the local record is marked synced and the outbox row removed.
5. On failure, classify: retryable (network, 5xx, timeout) vs terminal (validation, 4xx auth).
   Terminal failures surface to the user with a resolution path; retryable failures back off.

Rules:

- One outbox per account; clear it on logout to prevent cross-account leakage.
- Mutations must be idempotent server-side using the client-generated key.
- Ordering matters for dependent writes; sync parent before child or use a dependency graph.
- Bound the outbox: surface sync failures before the queue grows silently forever.

## Conflict Resolution

| Strategy | How it works | Use when |
|---|---|---|
| Last-write-wins (LWW) | Highest timestamp/revision wins | Low-stakes fields, independent edits |
| Per-field LWW | Merge at field granularity | Profiles, settings where fields rarely collide |
| Server authority | Server value always wins on conflict | Inventory, pricing, regulated data |
| Version vectors / optimistic concurrency | Client sends base revision; server rejects stale writes | Collaborative records where losing an edit is unacceptable |
| CRDTs | Data types merge deterministically | Rich text, lists, counters, true offline collaboration |

Rules:

- Pick the strategy per entity, not per app, and document it where the mapping lives.
- Resolve conflicts where the data is merged, not in the UI; UI only presents outcomes.
- Keep a conflict log for terminal cases so support can explain what happened.
- Never silently discard a user edit without surfacing it (badge, banner, or resolution sheet).
- Clocks lie: prefer server-assigned timestamps or logical clocks over device time.

## Background Sync

### iOS

- `BGTaskScheduler` (`BGAppRefreshTask`, `BGProcessingTask`) runs opportunistically; there is no
  guaranteed cadence and no background execution after user force-quit.
- Background `URLSession` for transfers; completion handlers must be called promptly.
- Push notifications with `content-available` wake the app briefly; do not abuse for polling.
- Budget and OS version determine what runs; design so sync progresses in small chunks.

### Android

- WorkManager with constraints (`NetworkType.CONNECTED`), unique work names, exponential backoff,
  and `ExistingWorkPolicy` semantics.
- Expedited work for user-visible actions, with quota awareness.
- Doze and battery restrictions throttle background work; foreground services need declared types
  and justification.
- Sync adapters are legacy; prefer WorkManager.

### Cross-platform frameworks

- React Native: `expo-background-task`/`expo-task-manager` wrap platform schedulers; background
  fetch intervals are OS-controlled, not promises.
- Flutter: `workmanager` or native scheduler plugins; verify current platform support and store
  policy compliance.

Rules:

- Sync on: app foreground, connectivity regain, push, and a low-frequency periodic task. Never poll
  aggressively.
- Make each sync step incremental and resumable; assume it can be killed at any moment.
- Merge background results into the local store, then let the UI observe the store; background
  tasks never touch UI state directly.

## Offline UX

- Show local data immediately with a subtle "syncing" indicator, not a blocking spinner.
- Mark pending items (clock/badge) and failed items distinctly (error affordance with retry).
- Optimistic UI with reconciliation: apply the write visually, then correct if the server rejects.
- Explain conflicts when user action is required; offer keep-mine/keep-theirs/save-both where the
  data supports it.
- Empty states differ for "no data" vs "not synced yet".
- Connectivity is a hint, not a gate: the request can still fail with connectivity present.

## Schema Migration and Evolution

- Version every local schema; migrations are forward-only code with tests from a real previous
  version's fixture.
- Server and client versions coexist during staged rollouts; the API must tolerate old clients
  (additive fields, no repurposing).
- Tombstones must outlive clients that still hold the deleted row; garbage-collect after a safe
  window.
- Encrypt at rest on device for sensitive data and plan key rotation without data loss.
- Backfills are explicit migration steps, not lazy code paths that assume new fields exist.

## Testing Sync

- Unit-test the conflict resolver and outbox state machine as pure logic.
- Integration-test repositories against an in-memory or temp-file SQLite with migration fixtures.
- Simulate: offline creation, queued edits, reconnect, partial sync kill, duplicate delivery,
  server rejection, clock skew, and cross-device concurrent edits.
- Property-based or fuzz tests for merge functions (commutativity, idempotence, convergence).
- Test multi-account switching and logout clearing local data.

## Anti-Patterns

- Network-first UI with a cache as an afterthought.
- Mutating server copies of data only when online; losing writes on crash.
- Using device timestamps as the only ordering signal.
- Hand-rolled sync without idempotency keys, tombstones, or a conflict policy.
- Sync loops: echoing server changes back as client mutations.
- Unbounded outbox with no error surfacing.
- Background tasks doing full-table syncs.
- Storing the local database unencrypted when it holds personal data.
- Treating "online" as a boolean from the OS without verifying the request.

## Checklist

- [ ] Local store is the source of truth for reads; writes are optimistic and queued.
- [ ] Outbox persisted transactionally with the mutation.
- [ ] Client-generated IDs and idempotent server mutations.
- [ ] Conflict strategy documented per entity; conflict log retained.
- [ ] Sync triggers: foreground, reconnect, push, low-frequency background.
- [ ] Background jobs idempotent, incremental, and resumable.
- [ ] Migration tests run from previous-version fixtures.
- [ ] Offline and error states designed, not default spinners.
- [ ] Logout clears local data and outbox for the signed-out account.

## Cross-Links

- Platform background APIs: [./02-ios.md](./02-ios.md), [./03-android.md](./03-android.md)
- Framework data layers: [./04-react-native.md](./04-react-native.md), [./05-flutter.md](./05-flutter.md)
- Performance impacts: [./07-performance.md](./07-performance.md)
- Encryption at rest: [./08-security.md](./08-security.md)
- Release compatibility: [./09-release-store-ci.md](./09-release-store-ci.md)
