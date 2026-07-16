---
name: senior-java-kotlin
description: Deep JVM patterns for Java 21+, Kotlin, Spring Boot, JPA, Gradle, JVM
  tuning, and Android
---

# Java / Kotlin

## Java 21+ Features

### Virtual Threads
```java
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    executor.submit(() -> handleRequest());
}

// Structured Concurrency (preview)
try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
    Future<User> user = scope.fork(() -> fetchUser(id));
    Future<Order> order = scope.fork(() -> fetchOrder(id));
    scope.join();
    scope.throwIfFailed();
    return new Response(user.resultNow(), order.resultNow());
}
```

### Pattern Matching
```java
sealed interface Shape permits Circle, Rect {}
record Circle(double radius) implements Shape {}
record Rect(double w, double h) implements Shape {}

double area(Shape s) {
    return switch (s) {
        case Circle c -> Math.PI * c.radius() * c.radius();
        case Rect r -> r.w() * r.h();
    };
}
```

### Records & Sealed Classes
```java
public record User(Long id, String name, String email) { }

public sealed abstract class Result<T>
    permits Success, Failure { }

public record Success<T>(T value) extends Result<T> { }
public record Failure<T>(String error) extends Result<T> { }
```

## Kotlin

### Coroutines
```kotlin
suspend fun fetchUser(id: Long): User = withContext(Dispatchers.IO) {
    api.getUser(id)
}

fun loadData() {
    scope.launch {
        val user = async { fetchUser(id) }
        val posts = async { fetchPosts(id) }
        updateUI(user.await(), posts.await())
    }
}
```

### Flow
```kotlin
fun observeData(): Flow<List<Item>> = flow {
    while (true) {
        emit(repository.getItems())
        delay(5000)
    }
}.flowOn(Dispatchers.IO)
```

### Sealed Classes
```kotlin
sealed class UiState {
    data object Loading : UiState()
    data class Success(val data: List<Item>) : UiState()
    data class Error(val message: String) : UiState()
}
```

## Spring Boot Patterns

```java
@RestController
@RequestMapping("/api/v1/users")
public class UserController {

    private final UserService service;

    @GetMapping("/{id}")
    public ResponseEntity<User> get(@PathVariable Long id) {
        return ResponseEntity.ok(service.findById(id));
    }
}

@Service
@Transactional
public class UserService {
    private final UserRepository repo;

    @Cacheable("users")
    public User findById(Long id) {
        return repo.findById(id)
            .orElseThrow(() -> new NotFoundException("User not found"));
    }
}
```

## JPA / Hibernate Optimization

- Use `@BatchSize` for collections.
- Prefer `JOIN FETCH` over `@EntityGraph` for simple cases.
- Use `StatelessSession` for bulk operations.
- Configure HikariCP: `maximumPoolSize=10`, `connectionTimeout=5000`.
- Enable `hibernate.query.plan_cache_max_size` for large apps.

## Gradle Configuration
```kotlin
plugins {
    kotlin("jvm") version "2.0.0"
    id("org.springframework.boot") version "3.3.0"
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

tasks.withType<Test> {
    useJUnitPlatform()
}
```

## JVM Tuning

```bash
# ZGC (low latency)
-XX:+UseZGC -XX:MaxGCPauseMillis=5 -Xms2g -Xmx2g

# G1GC (throughput)
-XX:+UseG1GC -XX:MaxGCPauseMillis=50 -XX:+ParallelRefProcEnabled
```

## Android (Jetpack Compose)

```kotlin
@Composable
fun UserScreen(viewModel: UserViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    when (val s = state) {
        is UiState.Loading -> LoadingIndicator()
        is UiState.Success -> UserList(s.data)
        is UiState.Error -> ErrorMessage(s.message)
    }
}

@HiltViewModel
class UserViewModel @Inject constructor(
    private val repo: UserRepository
) : ViewModel() {
    private val _state = MutableStateFlow<UiState>(UiState.Loading)
    val state: StateFlow<UiState> = _state.asStateFlow()
}
```

- **Room**: Use `@Transaction` for multi-table writes, `Flow` for reactive queries.
- **Hilt**: `@HiltViewModel`, `@Inject`, `@Module` for DI.
