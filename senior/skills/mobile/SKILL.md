---
description: "Deep mobile patterns for cross-platform decision guide, iOS, Android, React Native, and Flutter"
---

# Mobile

## Cross-Platform Decision Guide

| Criteria | SwiftUI | Jetpack Compose | React Native | Flutter |
|----------|---------|-----------------|--------------|---------|
| Performance | Native | Native | JS Bridge | Impeller |
| UI Fidelity | Native | Native | Approx | Pixel-perfect |
| Code Sharing | Apple only | Android only | 90%+ iOS/Android | 100% |
| Hot Reload | Preview | Compose | Fast Refresh | Hot Reload |
| Learning Curve | Moderate | Moderate | Low | Moderate |
| Ecosystem | Mature | Mature | Vast | Growing |

- **SwiftUI + UIKit**: Best for iOS-only apps.
- **Jetpack Compose**: Best for Android-only apps.
- **React Native / Expo**: Best for production cross-platform with web reuse.
- **Flutter**: Best for pixel-perfect custom UI and fast iteration.

## iOS (SwiftUI)

### MVVM with SwiftUI
```swift
@MainActor
@Observable
final class UserViewModel {
    var users: [User] = []
    var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        users = try! await api.fetchUsers()
    }
}

struct UserListView: View {
    @State private var vm = UserViewModel()
    var body: some View {
        List(vm.users, id: \.id) { user in
            Text(user.name)
        }
        .task { await vm.load() }
    }
}
```

### SwiftData
```swift
@Model
class User {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(inverse: \Order.user) var orders: [Order]
}

func fetchUsers() {
    let context = modelContext
    let descriptor = FetchDescriptor<User>(sortBy: [.init(\.name)])
    let users = try! context.fetch(descriptor)
}
```

### Security
- Keychain via `SecItemAdd`/`SecItemCopyMatching` for tokens.
- Biometric auth with `LocalAuthentication`.
- App Transport Security (ATS) enforces HTTPS.

## Android (Jetpack Compose)

### ViewModel + State
```kotlin
@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepo: AuthRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow<AuthUiState>(AuthUiState.Idle)
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    fun login(email: String, pass: String) {
        viewModelScope.launch {
            _uiState.value = AuthUiState.Loading
            authRepo.login(email, pass)
                .onSuccess { _uiState.value = AuthUiState.Success(it) }
                .onFailure { _uiState.value = AuthUiState.Error(it.message) }
        }
    }
}
```

### WorkManager
```kotlin
class SyncWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        return try {
            syncData()
            Result.success()
        } catch (e: Exception) {
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }
}
```

## React Native (Expo)

```bash
npx create-expo-app@latest --template blank-typescript
```

### Expo Router
```typescript
// app/(tabs)/index.tsx
export default function Home() {
  const { data } = useQuery({
    queryKey: ["users"],
    queryFn: () => api.getUsers(),
  });
  return <FlatList data={data} renderItem={({ item }) => <Text>{item.name}</Text>} />;
}
```

### EAS Build
```bash
eas build --platform ios --profile production
eas submit --platform ios
```

## Flutter

### Riverpod
```dart
@riverpod
class UserList extends _$UserList {
  @override
  Future<List<User>> build() => ref.watch(userRepositoryProvider).fetchAll();
}

class UserListWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(userListProvider);
    return users.when(
      data: (data) => ListView.builder(/* ... */),
      loading: () => CircularProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
    );
  }
}
```

### GoRouter
```dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => HomeScreen()),
    GoRoute(path: '/user/:id', builder: (_, state) =>
      UserScreen(id: state.pathParameters['id']!)),
  ],
);
```

## Mobile Security

- **OWASP Mobile Top 10**: M1 improper platform usage, M2 insecure data storage.
- Use `EncryptedSharedPreferences` (Android) / Keychain (iOS).
- Certificate pinning with `okhttp` / `URLSession`.
- Root/jailbreak detection.
- App integrity checks at runtime.

## App Store Deployment

- iOS: App Store Connect, TestFlight, code signing with Fastlane.
- Android: Google Play Console, internal/closed/open testing tracks.
- CI/CD: Fastlane with `match` for code signing.
