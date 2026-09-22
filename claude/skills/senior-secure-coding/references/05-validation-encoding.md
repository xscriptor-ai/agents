# Validation and Encoding

Scope: input validation strategy, schema validation, canonicalization, file uploads, path traversal, and output encoding for every context.

## Validation Strategy

Validation is a boundary concern: it decides what data is allowed to enter a component. It is not a
substitute for output encoding, authorization, or parameterization, and it should happen as close to
the trust boundary as possible.

1. Define the trust boundary for each component: HTTP handlers, queue consumers, CLI entrypoints,
   scheduled jobs reading external data, webhook receivers, and file parsers.
2. Validate every field for type, presence, length, range, format, and enum membership. Positive
   validation (allowlist) beats negative validation (denylist) in every case.
3. Reject rather than repair. "Cleaning" input produces surprising data and hides attacks; if the
   value is wrong, return a structured error.
4. Validate syntactic shape first, then semantic meaning (does this user exist, is this account
   number valid for this tenant, is this transition legal).
5. Never trust client-side validation; it is UX only. Revalidate server-side, including on internal
   service calls and replays.
6. Keep validation in one layer (DTO/schema/middleware) so tests cover it once and handlers receive
   typed, trusted values.
7. Bound everything: body size, field count, nesting depth, string length, array length, numeric
   range, file count, decompressed size. Unbounded input is a denial-of-service primitive.

### Schema validation by stack

| Stack | Library examples | Notes |
|---|---|---|
| Python | pydantic v2, attrs/cattrs, msgspec, marshmallow | Validate at the edge; use `extra="forbid"` |
| TypeScript/Node | Zod, Valibot, ArkType, JSON Schema (Ajv) | Infer types from schemas; parse, do not cast |
| Go | `encoding/json` + go-playground/validator, ozzo-validation | Struct tags plus explicit rules; distinguish zero values |
| Rust | serde + `deny_unknown_fields`, garde, validator | Types encode most invariants; validate the rest |
| Java/Kotlin | Bean Validation (Jakarta), JSON Schema validators | `@Valid` on controller DTOs; no entity binding from requests |
| C/C++ | hand-rolled parsers + fuzzing | Prefer a small typed parser; fuzz every entrypoint |

Rules that outlive library choice:

- Unknown fields are rejected or explicitly ignored by policy. Silent acceptance of extra fields
  enables mass assignment and smuggling.
- Enums are closed sets; never accept "any string representing a role" and compare later.
- Numeric inputs specify min/max and reject NaN/Infinity; parse integers from strings strictly.
- IDs are validated as opaque values, then checked for authorization at the data layer.
- Reject duplicate JSON keys or define deterministic behavior; parsers differ.
- Validate the `Content-Type` and parse according to the declared format; do not sniff into other
  parsers on mismatch.

## Canonicalization and Unicode

Canonicalize before validating or comparing. Validation on a non-canonical form can be bypassed by
an equivalent representation that the later consumer normalizes differently.

| Step | Risk if skipped |
|---|---|
| Decode percent-encoding exactly once | Double-decoding bypasses path/URL filters |
| Normalize Unicode (NFKC for identifiers) | Homoglyph and full-width bypasses |
| Case-fold or lower-case for case-insensitive fields | `ADMIN` vs `admin` mismatches |
| Normalize path separators and resolve `.`/`..` | Path traversal and allowlist bypass |
| Trim and normalize whitespace | Header/field smuggling, confusing comparisons |
| Strip control characters where not allowed | CRLF/header/log injection, terminal escapes |
| Reject invalid UTF-8 (do not silently replace) | Parser differentials, truncation attacks |

Encoding traps to remember: overlong UTF-8 sequences, percent-encoded nulls (`%00`), Unicode
normalization forms (NFC/NFD/NFKC/NFKD), bidi control characters in displayed names, zero-width
characters in identifiers and URLs, and mixed scripts in domains (IDN homograph attacks). Decide
which characters are legal for each field and reject everything else.

## File Uploads

File upload is the highest-risk input in most applications: it carries attacker bytes, attacker
names, attacker content types, and often ends up parsed by native code.

| Step | Requirement |
|---|---|
| Size | Enforce max bytes at the edge and again in code; stream to disk, never fully into memory |
| Count | Cap files per request and per account quota |
| Name | Discard the client name; generate a random name and keep the original only as display metadata (escaped) |
| Type | Determine by content sniffing (magic bytes) and/or decoding; treat `Content-Type` as a hint |
| Content | Re-encode images/documents with a hard-broken pipeline; do not pass bytes through |
| Storage | Store outside the web root or in object storage; never in a path derived from user input |
| Serving | Serve with `Content-Disposition: attachment`, `X-Content-Type-Options: nosniff`, and a dedicated domain |
| Execution | No execute permission; containers with read-only mounts; no shell-outs during validation |
| Archive | Prevent zip-slip and decompression bombs; limit ratios, entry counts, and nesting |
| Scanning | Malware scanning with quarantine; expose download only after the verdict |
| Lifecycle | Expiry, cleanup jobs, and deletion on account removal |

```python
import magic, secrets, pathlib

ALLOWED = {"image/png", "image/jpeg", "application/pdf"}
MAX_BYTES = 10 * 1024 * 1024
UPLOAD_ROOT = pathlib.Path("/var/app/uploads")

def store(upload) -> pathlib.Path:
    data = upload.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError("too large")
    if magic.from_buffer(data[:4096], mime=True) not in ALLOWED:
        raise ValueError("type not allowed")
    dest = UPLOAD_ROOT / secrets.token_hex(16)     # never use the client filename
    dest.write_bytes(data)
    return dest
```

SVG and HTML are executable documents: sanitize or forbid them, and never serve user-uploaded HTML
from the application origin. Image parsing libraries are a common RCE surface (ImageMagick policy,
libvips, browser-side decoders); keep them patched, sandboxed, and configured with resource limits.
For uploaded documents that will be previewed, use a conversion service with a hardened sandbox.

## Path Traversal

Filename and path parameters are prime traversal targets. The only reliable pattern is: resolve the
path, then verify it is inside an allowlisted base directory after symlink resolution.

```python
import pathlib

BASE = pathlib.Path("/srv/data").resolve()

def open_user_file(name: str):
    if name != pathlib.PurePath(name).name or "\x00" in name:
        raise ValueError("invalid name")             # reject separators and nulls
    candidate = (BASE / name).resolve()              # resolves .. and symlinks
    if not candidate.is_relative_to(BASE):           # Python 3.9+
        raise ValueError("escape attempt")
    return candidate.open("rb")
```

- Prefer opaque IDs mapped to paths in a database over user-supplied paths.
- If paths are required, allowlist characters and extensions, reject absolute paths, and check both
  the raw and the decoded/canonicalized form.
- Apply the check after symlink resolution; an in-base symlink can point anywhere.
- Watch archive extraction: each entry name must pass the same check (zip-slip), and absolute entry
  names and `..` segments must be rejected.
- On Windows, handle drive letters, UNC paths, alternate data streams (`:`), and short-name
  (`8.3`) forms; case-insensitive comparisons apply.

## Output Encoding Contexts

Encoding transforms data for one specific consumer. The same string may need multiple encodings in
one response, in order (for example URL-encode, then HTML-attribute-encode).

| Context | Correct mechanism | Common error |
|---|---|---|
| HTML text | HTML entity encoding | Using URL encoding in HTML |
| HTML attribute | Attribute encoding with quoted values | Forgetting quotes or using text encoding only |
| URL component | Percent-encoding of each component | Encoding the whole URL including scheme/host |
| JavaScript | JSON-encode + `\u` escaping; avoid inline script | Inserting into a script block unescaped |
| CSS | Allowlist values; avoid user data in `url()`/`expression` | "CSS escaping" functions that are not |
| SQL/NoSQL | Parameter binding | Manual quote doubling |
| OS command | argv arrays, no shell | `escapeshellarg` with a shell still in play |
| LDAP | RFC 4515 filter escaping / library builder | Quote doubling |
| XML | Entity encoding; no DTD for untrusted docs | `CDATA` wrapping with `]]>` inside |
| JSON | Serializer with correct headers and `nosniff` | String concatenation |
| CSV | Quote fields; neutralize leading `= + - @` and control chars | Excel formula execution |
| HTTP headers | Strip CR/LF; encode non-ASCII | Header/response splitting |
| Logs | Structured fields; escape control chars | Log forging, secret leakage |
| HTML rich text | Sanitizer allowlist (see [./02-xss-csrf.md](./02-xss-csrf.md)) | Home-grown tag stripping |

Encoding must happen at the last possible moment before the data crosses the boundary, using the
sink's own encoder. Double encoding (an encoder applied to already-encoded data) produces visible
garbage and can be its own vulnerability when a downstream component decodes once more.

## Error Handling and Limits

- Return structured, generic errors to clients; keep detail in server logs with a correlation ID.
  Never echo stack traces, SQL, file paths, or framework versions.
- Distinguish client errors (400/422) from authorization failures (403/404 by policy) without
  leaking object existence when that matters.
- Timeouts for every external call and expensive operation; limits on regex complexity, JSON depth,
  XML entity expansion, and decompression ratio.
- Fail closed: an error in an authorization or validation component must deny the request, not
  fall through to allow.

## Tests

- Table-driven invalid-input tests per endpoint: wrong types, empty, too long, too short, wrong
  charset, invalid UTF-8, duplicate keys, deeply nested JSON, huge arrays, NaN/Infinity.
- Property-based tests for parsers and normalizers (see [./08-review-checklist.md](./08-review-checklist.md)).
- Traversal tests with `..%2f`, `..%5c`, `%252e%252e`, absolute paths, nulls, and symlinked files.
- Upload tests with mismatched extension/content, polyglot files, zip bombs, and huge files.
- Encoding tests that render output and assert the browser/consumer sees inert data.
- Resource-limit tests that assert timeouts and 413/429 behavior under oversized input.

## Anti-Patterns

- Validating with a denylist of "bad characters" and calling it sanitization.
- Trusting `Content-Type`, file extension, or client-declared dimensions.
- Concatenating paths and checking for `".."` with a substring test.
- Applying one generic escaper to HTML, URLs, and JavaScript alike.
- Validating on the client and treating the server as already-validated.
- Decoding input twice ("to be helpful") and validating only the first pass.
- Accepting unknown JSON fields and binding them into entities (mass assignment).
- Unbounded regexes over user input (ReDoS) and unbounded decompression.

## Checklist

- [ ] Every trust boundary has a schema with positive validation and unknown-field policy.
- [ ] Size, count, depth, and numeric range limits are enforced before expensive work.
- [ ] Canonicalization order is documented: decode, normalize, validate, then store.
- [ ] Uploads are sniffed, re-encoded, randomly named, stored inert, and served safely.
- [ ] Path parameters resolve inside a base directory after symlink resolution.
- [ ] Every output sink uses the encoder for its context; encoding happens at the sink.
- [ ] Errors are generic to clients, detailed in protected logs, and fail closed.
- [ ] Tests include malformed encodings, traversal, polyglot uploads, and resource exhaustion.
