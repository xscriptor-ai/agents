---
description: "Deep Go patterns for project layout, concurrency, error handling, testing, and profiling"
---

# Go

## Project Layout
```
project/
  cmd/
    server/
      main.go
  internal/
    handler/
    service/
    repository/
    model/
  pkg/
    util/
  api/
    openapi.yaml
  migrations/
  test/
  go.mod
  go.sum
```

- `cmd/` for binary entry points.
- `internal/` for private packages (not importable outside).
- `pkg/` for public reusable libraries.

## Concurrency Patterns

### Worker Pool
```go
func worker(ctx context.Context, jobs <-chan Job, results chan<- Result) {
    for j := range jobs {
        select {
        case <-ctx.Done():
            return
        case results <- process(j):
        }
    }
}

func runPool(ctx context.Context, jobs []Job, workers int) []Result {
    jobCh := make(chan Job, len(jobs))
    resCh := make(chan Result, len(jobs))

    for range workers {
        go worker(ctx, jobCh, resCh)
    }
    for _, j := range jobs {
        jobCh <- j
    }
    close(jobCh)

    var results []Result
    for range jobs {
        results = append(results, <-resCh)
    }
    return results
}
```

### Fan-Out / Fan-In
```go
func fanOut(ctx context.Context, input <-chan int, workers int) []<-chan int {
    channels := make([]<-chan int, workers)
    for i := range workers {
        ch := make(chan int)
        channels[i] = ch
        go func() {
            defer close(ch)
            for v := range input {
                ch <- v * 2
            }
        }()
    }
    return channels
}

func fanIn(channels ...<-chan int) <-chan int {
    out := make(chan int)
    var wg sync.WaitGroup
    for _, ch := range channels {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for v := range ch {
                out <- v
            }
        }()
    }
    go func() {
        wg.Wait()
        close(out)
    }()
    return out
}
```

## Error Handling

### Wrapping
```go
import "fmt"

if err != nil {
    return fmt.Errorf("read config: %w", err)
}
```

### Sentinels
```go
var ErrNotFound = errors.New("not found")
var ErrConflict = errors.New("conflict")

if errors.Is(err, ErrNotFound) { }
```

### Custom Types
```go
type AppError struct {
    Code    int
    Message string
    Err     error
}

func (e *AppError) Error() string { return e.Message }
func (e *AppError) Unwrap() error { return e.Err }
```

## Interface Design
```go
type Repository interface {
    Get(ctx context.Context, id string) (Entity, error)
    List(ctx context.Context, filter Filter) ([]Entity, error)
    Create(ctx context.Context, e Entity) (Entity, error)
}

// Accept interfaces, return structs.
func NewService(repo Repository) *Service {
    return &Service{repo: repo}
}
```

## Testing

### Table-Driven
```go
func TestAdd(t *testing.T) {
    tests := []struct {
        name string
        a, b int
        want int
    }{
        {"positive", 1, 2, 3},
        {"negative", -1, -2, -3},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            if got := add(tt.a, tt.b); got != tt.want {
                t.Errorf("got %d, want %d", got, tt.want)
            }
        })
    }
}
```

### httptest
```go
func TestHandler(t *testing.T) {
    srv := httptest.NewServer(handler)
    defer srv.Close()

    resp, err := http.Get(srv.URL + "/health")
    // ...
}
```

## Profiling

```bash
go test -bench=. -cpuprofile=cpu.prof -memprofile=mem.prof
go tool pprof -http=:8080 cpu.prof
```

## Build

```makefile
LDFLAGS = -ldflags "-X main.version=$(VERSION) -w -s"
build:
  CGO_ENABLED=0 go build $(LDFLAGS) -o bin/server ./cmd/server
```

- Use `-ldflags` for version injection.
- `CGO_ENABLED=0` for static binaries.
- Docker multi-stage with `gcr.io/distroless/base`.
