# Injection

Scope: preventing attacker-controlled data from becoming code in SQL/NoSQL/ORM queries, OS commands, templates, LDAP filters, and XPath expressions.

## Root Cause and Universal Rules

Injection happens when data crosses into an interpreter as structure because the program built one
string with concatenation, formatting, or interpolation. The fix is always the same: keep code and
data structurally separate.

1. Bind values as parameters. Never format them into the statement.
2. Allowlist anything that cannot be parameterized: identifiers, sort direction, operators, engine
   names, template paths.
3. Validate type, length, and shape at the boundary before the value reaches any interpreter
   (see [./05-validation-encoding.md](./05-validation-encoding.md)).
4. Encode only at the output sink, per context. Escaping is a last resort, not a design.
5. Grant the interpreter least privilege: the DB account cannot run DDL or read other schemas, the
   process cannot spawn arbitrary binaries, the template engine cannot touch the filesystem.
6. Treat stored data from other users as untrusted (second-order injection): it may be concatenated
   later by a report builder, admin filter, or export job.

## SQL Injection

### Required pattern per stack

| Stack | Unsafe | Safe |
|---|---|---|
| Python DB-API | `cursor.execute(f"SELECT ... {v}")` | `cursor.execute("SELECT ... %s", (v,))` |
| psycopg 3 | f-string SQL | `%s` params; `sql.Identifier` for names |
| SQLAlchemy | `text(f"...")` | `text("... :id").bindparams(id=v)` or ORM filters |
| Django ORM | `raw(f"...")`, `.extra()` | ORM lookups; `raw("... %s", [v])` if unavoidable |
| Node `pg` | template literal with `${v}` | `$1` placeholders + values array |
| Knex | `whereRaw(f"...")` | `.where({ col: v })` or bindings array |
| Prisma | `$queryRawUnsafe` | `$queryRaw` tagged template |
| TypeORM | `.query(f"...")` | query builder with named params |
| JDBC | `Statement` + concat | `PreparedStatement` + `setX` |
| JPA/Hibernate | native query concat, HQL concat | `setParameter`, Criteria API |
| Go `database/sql` | `fmt.Sprintf` into query | `QueryContext(ctx, "... $1", v)` |
| .NET | `SqlCommand` concat | `Parameters.Add("@p", v)` |
| Rust sqlx | `format!` into query | `query!`/`query_as!` or `.bind(v)` |

Raw-query escape hatches still exist in every ORM; review every occurrence of `raw`, `text`,
`queryRaw`, `createNativeQuery`, `whereRaw`, `$executeRawUnsafe`, `em.createNativeQuery`, and
`execute_sql` and demand a binding or an allowlist.

### Identifiers, sort keys, and grammar positions

Most engines cannot bind identifiers, `ORDER BY`, `LIMIT`, `ASC/DESC`, or operator names. Map user
keys to constants; never quote user input as an identifier.

```python
SORTS = {"created": "created_at", "name": "lower(name)"}
direction = "DESC" if direction == "desc" else "ASC"
sort = SORTS.get(sort_key)
if sort is None:
    raise BadRequest("unknown sort key")
sql = f"SELECT id, name FROM items ORDER BY {sort} {direction}"
```

### LIKE and wildcard abuse

Treat `%` and `_` in user input as literal when the user is not supposed to write a pattern.
Escape them with a chosen escape character and declare it (`ESCAPE '\'`), or reject patterns and
offer structured filters instead. Bind the completed pattern as a value.

### ORM and second-order pitfalls

- Query builders are safe only when values flow through their parameter APIs; `literal()`,
  `sql.raw()`, and string fragments reintroduce injection.
- HQL/JPQL with `+` concatenation is as injectable as SQL.
- Stored values used in `ORDER BY`, dynamic reports, admin filters, and CSV exports are a common
  second-order path. Apply the same allowlists at read time.
- Over-posting (mass assignment) lets clients set fields they should not; bind DTOs with explicit
  field allowlists (see [./05-validation-encoding.md](./05-validation-encoding.md)).

### Database hardening

- One DB account per service; no DDL, no `SUPERUSER`, no cross-schema reads.
- Statement timeouts and row limits to blunt blind injection and denial of service.
- Disable or restrict dangerous features you do not need: `COPY ... PROGRAM`, `LOAD_FILE`,
  `INTO OUTFILE`, `xp_cmdshell`, stacked queries, `CREATE EXTENSION`.
- Return generic errors to clients; detailed SQL errors belong in server logs, not responses.

## NoSQL Injection

### MongoDB

The classic bug is passing a request body straight into a filter, allowing operator injection:

```js
// Attacker sends {"email": {"$gt": ""}} -> matches the first user
const user = await db.collection("users").findOne({ email: req.body.email });
```

```js
// Fix: enforce scalar type before the query
const email = req.body.email;
if (typeof email !== "string" || email.length > 254) throw new BadRequest("invalid email");
const user = await db.collection("users").findOne({ email });
```

Rules:
- Validate scalars; reject objects/arrays where a string is expected. Reject keys starting with `$`
  or containing `.` in user-supplied filter objects.
- `$where`, `$function`, `$accumulator`, and map-reduce execute JavaScript server-side: ban them
  with user data; if unavoidable, disable server-side scripting or sandbox with strict limits.
- `$regex`: treat user input as a literal by escaping regex metacharacters, or reject patterns.
  Bound pattern length and set regex timeouts to avoid ReDoS.
- Aggregation pipelines assembled from user input: allowlist stage and operator names; never let
  the client choose `$lookup`, `$out`, `$merge`, or `$function` freely.
- Mongoose schema typing and `strict` mode help, but do not replace explicit scalar checks.

### Redis

- Never pass user data into `EVAL`, `EVALSHA`, `FUNCTION`, `CONFIG`, `MODULE`, or `DEBUG`.
- Prefer high-level client APIs over raw `send_command` with interpolation.
- Use ACLs to restrict command families per workload; disable dangerous commands entirely.

### Search engines and document stores

- OpenSearch/Elasticsearch `query_string` parses a mini-language: do not accept raw user queries
  unless it is the product feature and you have scoped roles. Prefer the DSL with typed fields.
- Disable inline scripting where possible; restrict script sources and timeouts.
- Solr: avoid `json.query`/`stream.body` parameters reachable from users; apply parameter allowlists.

## OS Command Injection

| Language | Unsafe | Safe |
|---|---|---|
| Python | `os.system`, `subprocess(..., shell=True)` | `subprocess.run([exe, *args], shell=False, check=True)` |
| Node | `child_process.exec` | `execFile`/`spawn` with args array, `shell: false` |
| Go | `exec.Command("sh", "-c", ...)` | `exec.Command(binary, args...)` (never invokes a shell) |
| Java | `Runtime.exec(String)` | `new ProcessBuilder(List.of(exe, args...))` |
| .NET | concat into `FileName`/`Arguments` | `ProcessStartInfo.ArgumentList` |
| Ruby | backticks/`system(str)` | `system(*argv)`, `Open3.capture3(*argv)` |
| PHP | `exec`/`shell_exec`/`system` with interpolation | `proc_open` with array; `escapeshellarg` only as fallback |
| Rust | `sh -c` with formatted string | `Command::new(binary).args(args)` |

Shell metacharacters (`;`, `|`, `&`, `$()`, backticks, newlines, `<`, `>`) are the visible half of
the problem. The other half is argument injection: even without a shell, a value beginning with `-`
can change the target program's behavior (for example `scp -oProxyCommand=...`, `git --upload-pack`,
`curl -o`). Defenses:

- Prefer a library over spawning a process at all. Many "need shell" cases are really missing
  library calls (archive extraction, image conversion, DNS lookup, video probing).
- Use absolute binary paths from a fixed set; never let users choose the executable.
- Insert `--` before positional arguments when the tool supports it, and allowlist flags.
- Pass a clean environment (`env=` / `env_clear`); strip `PATH`, `LD_PRELOAD`, `BASH_ENV`, `IFS`.
- Validate every argument as if it were a query parameter: type, length, character allowlist.

```python
import subprocess, re

NAME = re.compile(r"\A[a-zA-Z0-9_-]{1,64}\Z")

def probe(name: str) -> bytes:
    if not NAME.match(name):
        raise ValueError("invalid name")
    return subprocess.run(
        ["/usr/bin/ffprobe", "-v", "quiet", "--", name],
        shell=False, capture_output=True, check=True, timeout=5,
    ).stdout
```

## Template Injection (SSTI)

Server-side template injection occurs when user input is compiled as a template instead of passed
as data. Every mainstream engine (Jinja2, Twig, Freemarker, Velocity, Thymeleaf, Handlebars, EJS,
Pug, Razor) evaluates expressions, and sandbox escapes are discovered regularly.

- Default: `render("page.html", content=user_text)`, never `render_string(user_text)`.
- Rich text is an output-encoding problem, not a template problem (see
  [./02-xss-csrf.md](./02-xss-csrf.md)).
- If user-authored templates are a product requirement: use a logic-less engine (Mustache),
  restrict the object model to plain data, render in a separate unprivileged process with CPU,
  memory, and wall-clock limits, and never expose imports, reflection, or filesystem helpers.
- Expression languages in config and logs are the same hazard: SpEL, OGNL, MVEL, Groovy, JEXL,
  and logging lookups (including the Log4Shell pattern) must never evaluate user input.
- Client-side, `eval`, `new Function`, and string-based `setTimeout` are template injection by
  another name; treat them as XSS sinks.

## LDAP and XPath

LDAP filters have their own grammar. Authentication code like
`(&(uid=USER)(password=PASS))` is bypassable with input such as `*)(uid=*` — and embedding a
password in a filter is wrong even when escaped.

- Escape filter values per RFC 4515 (`\`, `*`, `(`, `)`, NUL as `\5c`, `\2a`, `\28`, `\29`, `\00`).
- Escape distinguished names per RFC 4514 (`,`, `+`, `"`, `\`, `<`, `>`, `;`, `#`, leading/trailing
  spaces, leading `#`).
- Prefer a library filter builder; for authentication, do a search by identifier then a bind as the
  found DN, never a filter containing the password.
- Treat wildcard expansion as a feature you opt into, not a default.
- XPath has no bindings in most APIs: escape quotes and use single-quoted literals, or use the
  engine's variable API when available; prefer DOM traversal over string-built XPath for access
  control.

```python
import ldap.filter
safe = ldap.filter.escape_filter_chars(user_input)   # escape filter values
dn = ldap.dn.escape_dn_chars(uid)                    # escape DN components
```

## Adjacent Injection Classes

- **CRLF/header injection** — strip `\r` and `\n` (and encoded variants) from values placed into
  response headers, redirects, and emails.
- **Log injection / log forging** — encode or strip newlines and control characters before logging
  user data; prefer structured logging (JSON) so data stays in fields.
- **Regex injection / ReDoS** — do not build regexes from user input; if you must, escape
  metacharacters, bound length, and enforce timeouts (see
  [./05-validation-encoding.md](./05-validation-encoding.md)).
- **CSV formula injection** — values beginning with `=`, `+`, `-`, `@`, tab, or CR must be
  prefixed or quoted before export (see [./05-validation-encoding.md](./05-validation-encoding.md)).
- **Serialization injection** — covered in
  [./03-ssrf-deserialization.md](./03-ssrf-deserialization.md).

## Detection and Tests

- SAST/grep for formatting APIs near interpreter calls: `f"`, `%`, `+`, `format(`,
  `String.format`, template literals adjacent to `execute`, `query`, `exec`, `system`,
  `render`, `compile`.
- Unit tests with hostile payloads per sink: `' OR 1=1--`, `1; DROP TABLE`, `$(id)`,
  `` `id` ``, `{{7*7}}`, `${7*7}`, `*)(uid=*`, `..%2f`, `\u0000`.
- Integration tests that assert the DB role cannot run DDL and the process user cannot write
  outside its work directory.
- Error-path tests: force failures and assert no SQL, paths, or stack traces reach the response.

## Anti-Patterns

- "We escape quotes, so f-strings are fine" — escaping without a defined context is not escaping.
- Building `IN (?)` clauses by joining user strings instead of expanding bound placeholders.
- `ORDER BY` with validated "words" — validation must be an allowlist of known column names.
- Sanitizing on input in one place and concatenating later (second-order) in another.
- Trusting an ORM: raw fragments, `literal()`, and string-based `find` filters bypass its safety.
- Disabling server-side prepared statements to "improve performance" while concatenating values.
- Running the app's DB user with DDL rights "for migrations"; migrations get their own credential.
- Logging the full query with values on error, leaking secrets and user data.

## Checklist

- [ ] Every SQL/NoSQL/ORM call binds values; every raw escape hatch is reviewed and justified.
- [ ] Identifiers, sort keys, directions, and operators come from constant allowlists.
- [ ] No shell invocation with user data; argv arrays, absolute binaries, `--`, clean env.
- [ ] No user input compiled as a template or expression; logic-less engine if unavoidable.
- [ ] LDAP filter and DN values are escaped or built by a library; no password-in-filter auth.
- [ ] Interpreter credentials are least-privilege; timeouts and row limits are set.
- [ ] Errors are generic to clients and detailed only in protected logs.
- [ ] Regression tests exist for each fixed injection path, with the original payload.
