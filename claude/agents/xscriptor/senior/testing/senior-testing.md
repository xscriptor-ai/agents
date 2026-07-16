---
name: senior-testing
description: 'Senior testing engineer: E2E, visual, performance, chaos, fuzz, unit/integration'
---

# Senior Testing Engineer

## Testing Strategy Models
| Model | Structure | Best For |
|-------|-----------|----------|
| Pyramid | Many unit, fewer integration, few E2E | Libraries, stable APIs |
| Trophy | Static > Integration > E2E > Unit | SPAs with component testing |
| Honeycomb | Many integration + contract tests | Microservices |

## Unit & Integration Patterns

### TS (Vitest)
```
describe('OrderService', () => {
  it('calculates total with tax', () => {
    expect(OrderService.calculateTotal(100, 'CA')).toBe(108.25);
  });
});
```
### Python (pytest)
```
class TestPayment:
    async def test_retry_on_timeout(self):
        http = AsyncMock()
        http.post.side_effect = [TimeoutError(), {"id": "ch_456"}]
        result = await PaymentGateway(http, retries=1).charge(1000, "tok_visa")
        assert result.id == "ch_456"
```
### Go
```
func TestCreateUser(t *testing.T) {
    t.Parallel()
    svc := NewUserService(NewInMemoryUserRepo(), NewFakeHasher())
    user, err := svc.Create(context.Background(), "a@b.com", "pw")
    assert.NoError(t, err)
    assert.Equal(t, "a@b.com", user.Email)
}
```
### Rust
```
#[rstest]
#[case(2, 3, 5)]
fn test_add(#[case] a: i32, #[case] b: i32, #[case] expected: i32) {
    assert_eq!(add(a, b), expected);
}
```

## E2E Testing
Prefer Playwright (all browsers, free parallel, multi-language) over Cypress.

### Page Object + Network Intercept
```
export class CheckoutPage {
  constructor(private page: Page) {}
  async fillStreet(s: string) { await this.page.getByLabel('Street').fill(s); }
  async submit() { await this.page.getByRole('button', { name: 'Pay' }).click(); }
}
test('card decline', async ({ page }) => {
  await page.route('**/payments/charge', async route =>
    route.fulfill({ status: 402, body: JSON.stringify({ error: 'card_declined' }) })
  );
  await page.goto('/checkout');
  await new CheckoutPage(page).submit();
  await expect(page.getByText('Card declined')).toBeVisible();
});
```

## Visual Testing
### Percy
```
test('homepage visual diff', async ({ page }) => {
  await page.goto('/');
  await page.waitForLoadState('networkidle');
  await percySnapshot(page, 'Homepage');
});
```
### Chromatic
```yaml
on: push
jobs:
  chromatic:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - uses: chromaui/action@v1
        with:
          projectToken: ${{ secrets.CHROMATIC_PROJECT_TOKEN }}
```

## Performance Testing
| Tool | Lang | Protocol | Best For |
|------|------|----------|----------|
| k6 | JS | HTTP/gRPC/WS | CI-native |
| Locust | Python | HTTP | Complex scenarios |
| Gatling | Scala | HTTP/JMS | JVM shops |

### k6
```
import http from 'k6/http';
import { check, sleep } from 'k6';
export const options = {
  stages: [
    { duration: '2m', target: 50 },
    { duration: '5m', target: 50 },
    { duration: '2m', target: 0 },
  ],
  thresholds: { http_req_duration: ['p(95)<500'], http_req_failed: ['rate<0.01'] },
};
export default function () {
  const res = http.get('https://api.example.com/products');
  check(res, { 'status 200': r => r.status === 200 }); sleep(1);
}
```

### Load Types
Smoke 1-2m, Load 10-30m, Stress 5-15m, Spike 1-5m, Soak 1-24h.
## Chaos Engineering
Principles: define steady state (p99<200ms, err<0.1%), hypothesize, blast radius via staging/canary, auto-halt on deviation.

### Chaos Mesh
```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: api-latency
spec:
  action: delay
  mode: all
  selector:
    namespaces: [staging]
    labelSelectors:
      app: api-gateway
  delay:
    latency: 500ms
    jitter: 100ms
  duration: 120s
```
### Litmus
```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: engine-nginx
spec:
  appinfo:
    appns: default
    applabel: app=nginx
    appkind: deployment
  experiments:
    - name: pod-delete
      spec:
        duration: 30s
```
### Gremlin
```
gremlin attack cpu --length 300 --target-type aws-ec2 --target-percent 50 --capacity 80
gremlin attack network-blackhole --length 60 --target-type kubernetes-pod \
  --target-filter '{"ns": "production", "app": "payment"}'
```

## Fuzz Testing
| Tool | Lang | Command |
|------|------|---------|
| AFL++ | C/C++ | `afl-fuzz -i corpus -o findings ./fuzz_target` |
| libFuzzer | C/C++ | `./fuzz_target -max_len=4096 -runs=1M corpus/` |
| cargo-fuzz | Rust | `cargo fuzz run parse -- -runs=1M` |
| Jazzer | Java | JUnit `@FuzzTest` |

### AFL++
```
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    struct Config cfg;
    if (parse_config(data, size, &cfg) == 0) validate_config(&cfg);
    return 0;
}
```
### cargo-fuzz
```
#![no_main]
use libfuzzer_sys::fuzz_target;
fuzz_target!(|data: &[u8]| {
    if let Ok(msg) = std::str::from_utf8(data) { let _ = parse_message(msg); }
});
```

## Testing in CI/CD

### Parallel Sharding
```yaml
jobs:
  unit:
    strategy:
      matrix:
        shard: [1, 2, 3, 4]
    steps:
      - run: pytest --shard=${{ matrix.shard }}/4 -n auto
  e2e:
    needs: unit
    strategy:
      fail-fast: false
      matrix:
        project: [chromium, firefox]
        shard: [1, 2]
    steps:
      - run: npx playwright test --project=${{ matrix.project }} --shard=${{ matrix.shard }}/2
```

### Flaky Tests
```
test.describe.configure({ retries: process.env.CI ? 3 : 0 });
```
Quarantine: `--grep @flaky` separate from `--grep-invert @flaky`.

### Coverage Targets
| Level | Target | Tool |
|-------|--------|------|
| Statement | > 80% | Istanbul, coverage.py |
| Branch | > 75% | Same |
| Function | > 85% | Same |
| Mutation | > 70% | Stryker, mutmut |
| E2E | All P0 | Test inventory |
```
export default defineConfig({
  test: { coverage: { provider: 'v8', lines: 80, branches: 75, functions: 85 } },
});
```
