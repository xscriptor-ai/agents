# SSRF and Deserialization

Scope: server-side request forgery defenses and safe handling of serialized data across trust boundaries, with per-language unsafe APIs and migration paths.

## SSRF: Why It Happens

Any feature where the server fetches a URL chosen by a user is SSRF surface: webhooks, URL previews,
image proxies, PDF generators, RSS importers, file importers, analytics pixels, package installers,
CI runners, and "test connection" buttons. The attacker does not need the response back for impact:
blind SSRF can still hit internal APIs, cloud metadata, and admin panels.

The root cause is treating a URL as a destination when it is actually attacker-controlled input
that controls network access.

## Address-Level Defenses

| Target class | Examples | Rule |
|---|---|---|
| Loopback | `127.0.0.0/8`, `::1` | Block unless explicitly required |
| Private ranges | `10/8`, `172.16/12`, `192.168/16` | Block by default |
| Link-local | `169.254.0.0/16`, `fe80::/10` | Block; includes cloud metadata |
| Metadata | `169.254.169.254`, `fd00:ec2::254`, GCP/Azure equivalents | Block and require IMDSv2/hop limit |
| CGNAT | `100.64.0.0/10` | Block |
| Unique local | `fc00::/7` | Block |
| Wildcard / unspecified | `0.0.0.0`, `::` | Block |
| Public unicast | Everything else | Allow only through an egress allowlist |

Do not try to parse hostnames with regex. Resolve the name, then validate every returned address,
including IPv4-mapped IPv6 (`::ffff:127.0.0.1`) and alternate encodings (decimal, octal, hex,
shorthand like `127.1`). Normalize the URL with one parser, then extract and validate with the same
parser; parser differentials between validators and HTTP clients are a classic bypass.

## URL Validation Algorithm

1. Parse with the platform URL parser; reject unparsable input.
2. Allowlist schemes: `https` (and `http` only when required and constrained). Reject `file`,
   `gopher`, `ftp`, `dict`, `ldap`, `unix`, `jar`, and scheme-less forms.
3. Reject credentials in the URL (`user:pass@host`) unless you explicitly support them.
4. Resolve the hostname; reject if any address is in a blocked range. Pin the resolved IP and
   connect to that IP with the hostname in SNI/Host, so DNS cannot rebind between check and connect.
5. Optionally require the host to match an allowlist of domains for sensitive features.
6. Cap response size, redirects, and total time.
7. Disable or re-validate redirects: either do not follow them, or resolve and validate each hop,
   with a hard limit (for example 3). A public host can redirect to `169.254.169.254`.
8. Connect with a client that does not honor proxy environment variables, and strip headers that
   leak credentials (`Authorization`, `Cookie`, `X-Forwarded-*`, internal `Host`).

```python
import ipaddress, socket
from urllib.parse import urlparse

BLOCKED = [
    ipaddress.ip_network(n) for n in (
        "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
        "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16",
        "::1/128", "fc00::/7", "fe80::/10",
    )
]

def resolve_and_check(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme not in {"https", "http"} or not parsed.hostname:
        raise ValueError("scheme not allowed")
    infos = socket.getaddrinfo(parsed.hostname, parsed.port or 443, proto=socket.IPPROTO_TCP)
    ips = {info[4][0] for info in infos}
    for raw in ips:
        ip = ipaddress.ip_address(raw)
        if ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        if any(ip in net for net in BLOCKED):
            raise ValueError("address not allowed")
    return sorted(ips)[0]   # pin this IP in the HTTP client connection
```

This sketch is deliberately incomplete: production code must also handle the connection phase
(`Host` header, TLS `server_hostname`, no proxy inheritance), redirects, and response limits.

## Cloud Metadata Protections

- Enforce IMDSv2 (session-token-required) wherever the provider offers it, and set the hop limit to
  1 so container workloads cannot reach the metadata service.
- Prefer workload identity (OIDC federation, IRSA, GKE Workload Identity, managed identity) over
  instance credentials so metadata access has no value.
- Add network policy/egress firewall rules blocking `169.254.169.254` and link-local ranges from
  application namespaces.
- Azure and GCP metadata endpoints require specific headers; do not let user input set headers.

## Egress Architecture

The most reliable SSRF defense is network-level: the application cannot reach anything except an
explicit allowlist through a forward proxy.

| Layer | Control |
|---|---|
| Application | URL validation, IP pinning, scheme allowlist, response caps |
| Forward proxy | Allowlist of destinations, TLS inspection where appropriate, no proxy auth leakage |
| Network | Egress rules denying RFC1918, link-local, and metadata; DNS via controlled resolver |
| Identity | No ambient instance credentials reachable from app namespaces |

Blind SSRF detection: monitor outbound requests to unusual destinations, DNS queries to internal
names, and timing differences; log which user or feature initiated each outbound fetch. Cap
outbound request rates per account to slow scanning.

SSRF in non-HTTP protocols counts too: `gopher` and `dict` can speak to Redis/Memcached, `file` can
read local files, and some libraries follow `smb://` or `ldap://`. Scheme allowlisting is the fix.

## Deserialization: The Rule

Never deserialize native object formats from untrusted input. The safe boundary is: bytes from
untrusted source -> parse with a schema-aware, non-executable format -> validate fields.

| Language | Unsafe APIs | Safe alternatives |
|---|---|---|
| Java | `ObjectInputStream`, `readObject`, XStream, SnakeYAML `load`, Fastjson autotype, Kryo, Jackson `enableDefaultTyping` | JSON with a fixed DTO; `PolymorphicTypeValidator` if polymorphism is required; SnakeYAML `SafeConstructor` |
| Python | `pickle`, `dill`, `marshal`, `yaml.load` (default loader), `eval` of literals | `json`, `yaml.safe_load`, `pydantic` for validation |
| Ruby | `Marshal.load`, `YAML.unsafe_load`, `Oj` with object mode | `JSON.parse` with explicit schema handling |
| PHP | `unserialize` without `allowed_classes` | `json_decode`; `unserialize(..., ['allowed_classes' => false])` |
| .NET | `BinaryFormatter`, `NetDataContractSerializer`, `LosFormatter`, `TypeNameHandling.All/Objects` | `System.Text.Json`, `DataContractSerializer` with known types |
| Node | `node-serialize`, `serialize-javascript` evaluated, `vm` as a sandbox | `JSON.parse` with schema validation; `node:vm` is not a security boundary |
| Go | `encoding/gob` across trust boundaries, `yaml.Unmarshal` into `interface{}` | `encoding/json` into typed structs; validate with a schema |
| Rust | Serde into `Value` then unchecked casts; `bincode` across trust boundaries | Typed structs, `deny_unknown_fields`, schema validation |

Even "safe" formats need care: huge payloads cause memory exhaustion, deeply nested JSON causes
stack exhaustion, duplicate keys and type confusion break naive validation, and JSON numbers lose
precision (money, IDs). Apply size limits, depth limits, strict schemas, and explicit numeric
handling.

## Signed State and Tokens

When state must round-trip through the client (cart, filters, OAuth `state`, signed cookies):

- Serialize to a canonical JSON (or CBOR) representation with a schema version.
- Sign with a modern MAC or signature over the exact bytes (HMAC-SHA-256 with a keyed secret, or
  Ed25519); include a version, issue time, and expiry inside the signed payload.
- Verify before parsing into domain objects; reject unknown versions rather than guessing.
- Keep keys out of the token; rotate with a `kid` and accept an overlap window.
- Never use encryption as integrity: encrypt-then-MAC or AEAD only (see
  [./04-crypto-secrets.md](./04-crypto-secrets.md)). Do not trust encrypted-but-unsigned payloads;
  attackers can often manipulate them.

## Deserialization Gadget Chains

Java and .NET deserialization bugs become remote code execution through gadget chains available on
the classpath (commons-collections, Spring, Groovy, and countless others). You cannot enumerate all
gadgets, so do not accept native serialized data at all.

- Remove the capability: delete `ObjectInputStream` usage, disable Java serialization endpoints,
  and block JNDI lookups where the runtime allows.
- If legacy protocols require Java serialization internally, apply a strict object-input filter
  allowlist (`jdk.serialFilter`), authenticate the sender, and keep the protocol off untrusted
  networks.
- Audit libraries that deserialize implicitly: session stores, cache values, message queues, RMI,
  JMX, RPC frameworks, and view-state (ASP.NET `ViewState` needs MAC enforcement).
- Jackson: never enable default typing globally; use a `PolymorphicTypeValidator` with an explicit
  allowlist, or avoid polymorphic types in API-facing DTOs.

## Migration Notes

- Replace pickle/YAML-unsafe/Java-serialization session formats with JSON plus HMAC (or server-side
  sessions) behind a feature flag; invalidate old tokens at cutover.
- For internal RPC, move from Java serialization or .NET BinaryFormatter to protobuf/gRPC, which
  do not construct arbitrary objects.
- Treat cache poisoning via deserialization as an incident class: purge caches when changing formats.
- Add a deserialization lint rule (for example ban `pickle.loads`, `Marshal.load`, `BinaryFormatter`)
  and a test that feeds each endpoint malformed and oversized payloads.

## Anti-Patterns

- Denylisting hostnames (`localhost`, `metadata.google.internal`) instead of validating resolved IPs.
- Validating a URL, then passing the original string to the HTTP client (TOCTOU with DNS rebinding).
- Following redirects without re-validating each hop.
- Allowing user-controlled headers (`X-Forwarded-Host`, `Host`, custom auth) on outbound fetches.
- Relying on `node:vm`, a regex, or a WAF as a deserialization sandbox.
- Signing data with a symmetric secret but not verifying before parsing.
- Storing a serialized object in a cookie or hidden field because "the user cannot modify it".

## Checklist

- [ ] Every outbound fetch from user input validates scheme, resolved IP, and redirects; the
      resolved IP is pinned for the connection.
- [ ] Egress firewall blocks metadata and private ranges; workload identity replaces instance keys.
- [ ] Response size, timeout, and redirect count are capped; per-user outbound rate limits exist.
- [ ] No native deserialization (`pickle`, `ObjectInputStream`, `Marshal`, `BinaryFormatter`,
      `unserialize`, unsafe YAML) on untrusted input; a lint rule enforces it.
- [ ] Client-round-tripped state is signed, versioned, expires, and is schema-validated before use.
- [ ] JSON parser has size and depth limits; validation rejects unknown/duplicate fields.
- [ ] Tests cover redirect-to-metadata, DNS rebinding, oversized payloads, and malformed state.
