# Replay

> [!CAUTION]
> This package is in active development, and may make breaking changes before an initial release.

HTTP recording, playback, and stubbing for Swift,
built around **HAR (HTTP Archive)** fixtures and **Swift Testing** traits.

## Requirements

- Swift 6.1+
- macOS 14+ / iOS 17+ / tvOS 17+ / watchOS 10+ / visionOS 1+

## Installation

### Swift Package Manager (Swift Package Manager)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mattt/Replay.git", branch: "main")
]
```

Then add `Replay` to your **test target** dependencies:

```swift
.testTarget(
    name: "YourTests",
    dependencies: [
        .product(name: "Replay", package: "Replay")
    ]
)
```

### Xcode

1. Add the package: **File → Add Packages…**
2. Add **Replay** to your **test target**.

If you want to ship HAR files in your test bundle, 
ensure they’re included as test resources (see the tutorial below).

## Quick start

```swift
import Foundation
import Testing
import Replay

struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

@Suite(.serialized, .playbackIsolated(replaysFrom: Bundle.module))
struct MyAPITests {
    @Test(.replay("fetchUser"))
    func fetchUser() async throws {
        let (data, _) = try await URLSession.shared.data(
            from: URL(string: "https://api.example.com/users/42")!
        )
        let user = try JSONDecoder().decode(User.self, from: data)
        #expect(user.id == 42)
    }
}
```

`Bundle.module` is a Swift Package Manager feature.
In an Xcode test target you typically point Replay at your test bundle’s resources:

```swift
import Foundation
import Testing
import Replay

private final class TestBundleToken {}

@Suite(
    .serialized,
    .playbackIsolated(
        replaysRootURL: Bundle(for: TestBundleToken.self)
            .resourceURL?
            .appendingPathComponent("Replays")
    )
)
struct MyAPITests {
    @Test(.replay("fetchUser"))
    func fetchUser() async throws {
        let (data, _) = try await URLSession.shared.data(
            from: URL(string: "https://api.example.com/users/42")!
        )
        _ = data
    }
}
```

## Getting STarted

Let's walk through a simple end-to-end setup.

### 1) Make sure your API client can accept a session (optional but recommended)

Replay can intercept `URLSession.shared` globally, 
so you *can* skip dependency injection.
But accepting a session makes it easy to opt into `.test` scope later 
(and it’s generally good design).

```swift
import Foundation

struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

struct ExampleAPIClient {
    let baseURL: URL
    let session: URLSession

    init(
        baseURL: URL = URL(string: "https://api.example.com")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchUser(id: Int) async throws -> User {
        let url = baseURL.appendingPathComponent("users/\(id)")
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(User.self, from: data)
    }
}
```

### 2) Add a `Replays/` folder to your test target

Replay loads archives named `Replays/<name>.har`.

#### Swift Package Manager: copy fixtures into the test bundle

Create:

```
Tests/YourTests/Replays/
```

Then in `Package.swift`, add:

```swift
.testTarget(
    name: "YourTests",
    dependencies: [
        .product(name: "Replay", package: "Replay")
    ],
    resources: [
        .copy("Replays")
    ]
)
```

#### Xcode: include fixtures as test resources

Add your `Replays/` folder to the test target and ensure it’s included in the test bundle resources.

If you want Replay to load fixtures from your test bundle resources, you’ll also want to apply:

```swift
private final class TestBundleToken {}

@Suite(
    .playbackIsolated(
        replaysRootURL: Bundle(for: TestBundleToken.self)
            .resourceURL?
            .appendingPathComponent("Replays")
    )
)
struct YourSuite { /* ... */ }
```

### 3) Write a test using `.replay("…")`

```swift
import Foundation
import Testing
import Replay

struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

@Suite(.serialized, .playbackIsolated(replaysFrom: Bundle.module))
struct ExampleAPITests {
    @Test(.replay("fetchUser"))
    func fetchUser() async throws {
        let client = ExampleAPIClient()
        let user = try await client.fetchUser(id: 42)

        #expect(user.id == 42)
    }
}
```

### 4) Run tests (playback-only by default)

The first run should fail if `Replays/fetchUser.har` doesn’t exist yet.
That’s expected — Replay is designed to prevent accidental “record-on-first-run”.

```bash
swift test
```

### 5) Record intentionally

Enable recording for a single test (recommended), or an entire suite:

```bash
# Record one test
REPLAY_MODE=record swift test --filter ExampleAPITests.fetchUser
```

This will create `Replays/fetchUser.har`.

> [!TIP]
> **Run against the live API (skip replay + no recording)**
>
> If you want to run tests against a real (production/staging) API without touching fixtures,
> keep your `.replay("…")` traits in place and pass:
>
> ```bash
> REPLAY_MODE=live swift test --filter ExampleAPITests.fetchUser
> ```
>
> - **No fixture required**: missing `Replays/*.har` won’t fail the test.
> - **No fixture writes**: nothing is recorded or modified.

### 6) Re-run (back to playback-only)

```bash
swift test
```

### 7) Commit fixtures safely

> [!WARNING]
> HAR files may contain sensitive data (cookies, auth headers, tokens, PII).
> Always review/redact before committing to source control.

Replay can redact while recording (recommended) or you can filter an existing HAR file using the plugin (see Tooling).

## Common patterns and recipes

### Matching strategy (make fixtures stable)

The default matchers are **method + full URL** (including query).
That’s great for fully deterministic endpoints, 
but many APIs have volatile query items 
(pagination cursors, timestamps, cache-busters).

A very common stable setup is **method + path**:

```swift
@Test(.replay("fetchUser", matching: [.method, .path]))
func fetchUser() async throws { /* ... */ }
```

Available matchers:
- `.method`
- `.url` (full absolute URL including query)
- `.host`
- `.path`
- `.query`
- `.headers([String])`
- `.body`
- `.custom((URLRequest, URLRequest) -> Bool)`

### Filtering (redacting secrets while recording)

Filters run during recording and are persisted into the HAR file.

```swift
@Test(
    .replay(
        "fetchUser",
        matching: [.method, .path],
        filters: [
            .headers(removing: ["Authorization", "Cookie"]),
            .queryParameters(removing: ["token", "api_key"])
        ]
    )
)
func fetchUser() async throws { /* ... */ }
```

Body filters:
- `Filter.body(replacing:with:)` for simple string redaction
- `Filter.body(decoding:transform:)` for “decode JSON, redact, re-encode”

### Stubbing (no HAR file)

Sometimes you want a tiny explicit stub instead of a fixture file.

```swift
import Testing
import Replay

@Test(
    .replay(
        stubs: [Stub(URL(string: "https://example.com/hello")!, status: 200, body: "OK")]
    )
)
func stubbedRequest() async throws {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://example.com/hello")!)
    #expect(String(data: data, encoding: .utf8) == "OK")
}
```

### Parallel tests: use `.test` scope + `Replay.session`

By default, `.replay` uses global `URLProtocol` registration and a shared store, 
which is why `.serialized` is recommended when multiple tests use Replay.

If you want to isolate by test/task, 
use `scope: .test` **and** make requests through a session created by Replay:

```swift
@Suite(.playbackIsolated(replaysFrom: Bundle.module))
struct ParallelizableAPITests {
    @Test(.replay("fetchUser", matching: [.method, .path], scope: .test))
    func fetchUser() async throws {
        let client = ExampleAPIClient(session: Replay.session)
        _ = try await client.fetchUser(id: 42)
    }
}
```

### Multiple replays (many fixtures)

Replay supports **multiple HAR archives** by keeping many files in your `Replays/` directory 
and selecting **one archive per test** by name.

```
Tests/YourTests/Replays/
├── createPost.har
├── fetchPosts.har
└── fetchUser.har
```

```swift
import Testing
import Replay

@Suite(.serialized, .playbackIsolated(replaysFrom: Bundle.module))
struct ExampleAPITests {
    @Test(.replay("fetchUser", matching: [.method, .path]))
    func fetchUser() async throws { /* ... */ }

    @Test(.replay("fetchPosts", matching: [.method, .path]))
    func fetchPosts() async throws { /* ... */ }

    @Test(.replay("createPost", matching: [.method, .path]))
    func createPost() async throws { /* ... */ }
}
```

Don’t stack multiple `.replay(...)` traits on the same test. 
Treat Replay as **one active configuration per test scope**:

```swift
@Test(.replay("fetchUser"), .replay("fetchPosts")) // ❌ Don't do this
func myTest() async throws { /* ... */ }
```

If you need a single test to cover multiple calls, 
you usually have two practical options:

- **Option A (recommended)**: 
  record those calls into **one HAR file** 
  (one archive can contain many request/response entries).
- **Option B**: 
  split the scenario into multiple tests, 
  each with its own `@Test(.replay("…"))`.

### Using Replay without Swift Testing

If you’re not using Swift Testing (or you want explicit control), use the lower-level APIs:
- `Playback.session(configuration:)` to replay from a HAR file (or in-memory stubs)
- `Capture.session(configuration:)` to record traffic to a HAR file (or to a handler)
- `HAR.load(from:)` / `HAR.save(_:to:)` to read/write archives

Example: replay from a file with strict matching:

```swift
let archiveURL = URL(fileURLWithPath: "Replays/fetchUser.har")
let config = PlaybackConfiguration(source: .file(archiveURL), mode: .strict, matchers: [.method, .path])
let session = try await Playback.session(configuration: config)
// use `session` to make requests
```

Example: allow unknown requests to hit the network (useful while migrating to fixtures):

```swift
let config = PlaybackConfiguration(source: .file(archiveURL), mode: .passthrough, matchers: [.method, .path])
let session = try await Playback.session(configuration: config)
```

Example: record and append new requests to an existing HAR file:

```swift
let config = PlaybackConfiguration(source: .file(archiveURL), mode: .record, matchers: [.method, .path])
let session = try await Playback.session(configuration: config)
```

## Tooling

Replay includes a Swift Package Manager command plugin to help manage HAR archives.

> [!NOTE]
> You may need `--allow-writing-to-package-directory` the first time you run commands that modify files.

```bash
# Check status of archives (age, orphans, etc.)
swift package replay status

# Record specific tests (wrapper around swift test)
swift package replay record ExampleAPITests.fetchUser

# Inspect a HAR file
swift package replay inspect Tests/YourTests/Replays/fetchUser.har

# Validate a HAR file
swift package replay validate Tests/YourTests/Replays/fetchUser.har

# Filter sensitive data from an existing HAR
swift package replay filter input.har output.har --headers Authorization --query-params token
```

## Troubleshooting

### “Replay Archive Missing”

This is expected on first run (unless you’ve already created `Replays/<name>.har`).
Record intentionally for the failing test:

```bash
REPLAY_MODE=record swift test --filter <your-test-name>
```

### “No Matching Entry in Archive”

This means the test made a request that didn’t match any entry in the HAR.
Common fixes:
- Use a more stable matcher set (often `.method, .path` instead of full `.url`)
- Re-record the fixture intentionally
- Inspect the archive to see what it contains:

```bash
swift package replay inspect path/to/archive.har
```

## CI guidance

- Replay only records when explicitly enabled (for example `REPLAY_MODE=record`), so your CI runs stay playback-only by default.
- Commit fixtures and keep them reviewed/redacted, just like any other test asset.

## Creating HAR files from browser sessions

Sometimes it’s easier to capture HTTP traffic using your browser’s developer tools rather than recording through tests.
All major browsers can export network activity as HAR files.

> [!WARNING]
> HAR files may contain sensitive data including cookies, authentication tokens, passwords, and personal information.
> Always review and redact sensitive data before committing HAR files to version control.

### Safari

1. Enable the Develop menu: **Safari → Settings → Advanced → Show features for web developers**
2. Open Developer Tools: **Develop → Show Web Inspector** (or <kbd>⌥⌘I</kbd>)
3. Select the **Network** tab
4. Trigger the API calls you want to capture
5. Right-click in the network list and choose **Export HAR**

### Chrome

1. Open Developer Tools: **View → Developer → Developer Tools** (or <kbd>⌥⌘I</kbd>)
2. Select the **Network** tab
3. Trigger the API calls you want to capture
4. Click the **↓** (download) button and choose **Save all as HAR with content**

### Firefox

1. Open Developer Tools: **Tools → Browser Tools → Web Developer Tools** (or <kbd>⌥⌘I</kbd>)
2. Select the **Network** tab
3. Trigger the API calls you want to capture
4. Right-click in the network list and choose **Save All As HAR**

## License

This project is available under the MIT license.
See the LICENSE file for more info.
