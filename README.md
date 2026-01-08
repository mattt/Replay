# Replay

HTTP recording, playback, and stubbing for Swift,
built around <a href="https://en.wikipedia.org/wiki/HAR_(file_format)"><abbr title="HTTP Archive">HAR</abbr> fixtures</a>
and [Swift Testing traits](https://developer.apple.com/documentation/testing/traits).

Inspired by Ruby's [VCR](https://github.com/vcr/vcr) and
Python's [VCR.py](https://github.com/kevin1024/vcrpy) / [pytest-recording](https://github.com/kiwicom/pytest-recording).

---

Add the `.replay` trait to a `@Test` declaration to specify a HAR file
containing prerecorded HTTP responses:

```swift
import Foundation
import Testing
import Replay

struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

@Test(.replay("fetchUser"))
func fetchUser() async throws {
    // Replay intercepts HTTP request and returns a prerecorded response
    let (data, _) = try await URLSession.shared.data(
        from: URL(string: "https://api.example.com/users/42")!
    )
    let user = try JSONDecoder().decode(User.self, from: data)
    #expect(user.id == 42)
}
```

The `.replay("fetchUser")` trait loads responses from `Replays/fetchUser.har`.

<details>
<summary><code>fetchUser.har</code> contents</summary>

```json
{
  "log": {
    "version": "1.2",
    "creator": {
      "name": "Replay/1.0",
      "version": "1.0"
    },
    "entries": [
      {
        "startedDateTime": "2025-12-30T09:41:00.000Z",
        "time": 150,
        "request": {
          "method": "GET",
          "url": "https://api.example.com/users/42",
          "httpVersion": "HTTP/1.1",
          "cookies": [],
          "headers": [{ "name": "Accept", "value": "application/json" }],
          "queryString": [],
          "headersSize": -1,
          "bodySize": 0
        },
        "response": {
          "status": 200,
          "statusText": "OK",
          "httpVersion": "HTTP/1.1",
          "cookies": [],
          "headers": [{ "name": "Content-Type", "value": "application/json" }],
          "content": {
            "size": 52,
            "mimeType": "application/json",
            "text": "{\"id\":42,\"name\":\"Alice\",\"email\":\"alice@example.com\"}"
          },
          "redirectURL": "",
          "headersSize": -1,
          "bodySize": 52
        },
        "cache": {},
        "timings": {
          "send": 0,
          "wait": 150,
          "receive": 0
        }
      }
    ]
  }
}
```

</details>

Replay can also stub responses inline:

```swift
import Foundation
import Testing
import Replay

@Test(
    .replay(
        stubs: [
            .get(
                "https://example.com/greeting",
                200,
                ["Content-Type": "text/plain"],
                { "Hello, world!" }
            )
        ]
    )
)
func fetchGreeting() async throws {
    // Replay intercepts HTTP request and returns the stubbed response
    let (data, _) = try await URLSession.shared.data(
        from: URL(string: "https://example.com/greeting")!
    )
    #expect(String(data: data, encoding: .utf8) == "Hello, world!")
}
```

## Requirements

- Swift 6.1+
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+ / visionOS 1+ / Linux

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mattt/Replay.git", from: "0.2.0")
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

## Getting Started

### 0. Design your HTTP client to accept a session (optional)

Replay can intercept `URLSession.shared` globally,
but accepting a `URLSession` parameter enables parallel test execution
and is generally good practice.

```swift
import Foundation

struct User: Identifiable, Codable {
    let id: Int
    let name: String
    let email: String
}

actor ExampleAPIClient {
    static let shared = ExampleAPIClient()

    let baseURL: URL
    let session: URLSession

    init(
        baseURL: URL = URL(string: "https://api.example.com")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchUser(id: User.ID) async throws -> User {
        let url = baseURL.appendingPathComponent("users/\(id)")
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(User.self, from: data)
    }
}
```

### 1. Add a `Replays/` folder to your test target

Replay loads archives named `Replays/<name>.har`.

Create a `Replays/` directory alongside your test files:

```shell
mkdir Tests/YourTests/Replays/
```

#### Swift Package Manager: Copy fixtures into the test bundle

In `Package.swift`, add:

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

Use the `.playbackIsolated` test suite trait
to point Replay at your package bundle:

```swift
import Foundation
import Testing
import Replay

@Suite(.playbackIsolated(replaysFrom: Bundle.module))
```

#### Xcode: Include fixtures as test resources

Add your `Replays/` folder to the test target and ensure it's included in the test bundle resources.

Use the `.playbackIsolated` test suite trait
to point Replay at your test bundle's resources:

```swift
import Foundation
import Testing
import Replay

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

### 2. Write a test using `.replay("…")`

```swift
import Foundation
import Testing
import Replay

@Suite(/* ... */)
struct YourSuite {
    @Test(.replay("fetchUser"))
    func fetchUser() async throws {
        let client = ExampleAPIClient.shared
        let user = try await client.fetchUser(id: 42)
        #expect(user.id == 42)
    }
}
```

### 3. Run tests

The first run fails if the HAR file doesn't exist yet—this is intentional
to prevent accidental recording.

Replay uses two environment variables to control behavior:

- **`REPLAY_RECORD_MODE`** (default: `none`)
  - `none`: never record
  - `once`: record only if the archive is missing
  - `rewrite`: rewrite the archive from scratch
- **`REPLAY_PLAYBACK_MODE`** (default: `strict`)
  - `strict`: require fixtures; fail if missing/unmatched
  - `passthrough`: use fixtures when available; otherwise hit the network
  - `live`: ignore fixtures and always hit the network

```console
$ swift test
❌  Test fetchUser() recorded an issue at ExampleTests.swift
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  No Matching Entry in Archive
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Request: GET https://api.example.com/users/42
Archive: /path/to/.../Replays/fetchUser.har

This request was not found in the replay archive.

Options:
1. Run against the live network (ignore fixtures):
   REPLAY_PLAYBACK_MODE=live swift test --filter <test-name>

2. Rewrite the archive from scratch:
   REPLAY_RECORD_MODE=rewrite swift test --filter <test-name>

3. Check if request details changed (URL, method, headers)
   and update test expectations

4. Inspect the archive:
   swift package replay inspect /path/to/.../Replays/fetchUser.har

```

### 4. Record

```bash
REPLAY_RECORD_MODE=once swift test --filter YourSuite.fetchUser
```

This creates `Replays/fetchUser.har`.

> [!TIP]
> To run tests against a live API (ignoring fixtures), use `REPLAY_PLAYBACK_MODE=live`.

### 5. Re-run

```console
$ swift test
✅  Test fetchUser() passed after 0.001 seconds.
```

### 6. Commit fixtures

Replay can redact while recording using filters (recommended)
or you can filter an existing HAR file using the plugin (see Tooling).

> [!WARNING]
> HAR files may contain sensitive data (cookies, auth headers, tokens, PII).
> Always review/redact before committing to source control.

## Usage

### Matching strategies

By default, Replay matches requests by HTTP method + full URL,
which requires scheme, host, port, path, query, and fragment to match exactly.
For APIs with volatile query parameters (pagination cursors, timestamps, cache-busters),
use a looser matching strategy:

```swift
@Test(.replay("fetchUser", matching: [.method, .path]))
func fetchUser() async throws { /* ... */ }
```

Matchers compose with `AND` semantics;
all must match for an entry to be selected.

| Matcher         | Matches on                                           |
| --------------- | ---------------------------------------------------- |
| `.method`       | HTTP method (case-insensitive)                       |
| `.url`          | Full URL string (strict)                             |
| `.host`         | URL host                                             |
| `.path`         | URL path                                             |
| `.query`        | Query parameters (order-insensitive)                 |
| `.headers([…])` | Specified header values (names are case-insensitive) |
| `.body`         | Request body bytes                                   |
| `.custom(…)`    | Custom `(URLRequest, URLRequest) -> Bool`            |

> [!TIP]
> If built-in matchers don't cover your needs,
> use `.custom` to implement arbitrary matching logic.

### Filters

Filters strip sensitive data during recording:

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

For request/response bodies, use `Filter.body(replacing:with:)` for string redaction
or `Filter.body(decoding:transform:)` to transform decoded JSON.

### Stubs

For simple cases, use inline stubs instead of HAR files:

```swift
@Test(
    .replay(
        stubs: [.get("https://example.com/greeting", 200, ["Content-Type": "text/plain"], { "Hello, world!" })]
    )
)
func fetchGreeting() async throws {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://example.com/greeting")!)
    #expect(String(data: data, encoding: .utf8) == "Hello, world!")
}
```

### Parallel test execution

By default, Replay uses global `URLProtocol` registration with serialized access
to prevent cross-test interference.
This means tests using `.replay()` run one at a time,
even when Swift Testing would otherwise run them in parallel.

For true parallel execution, use `scope: .test` to isolate each test's playback state:

```swift
@Suite(.playbackIsolated(replaysFrom: Bundle.module))
struct ParallelizableAPITests {
    @Test(.replay("fetchUser", matching: [.method, .path], scope: .test))
    func fetchUser() async throws {
        // Use Replay.session instead of URLSession.shared
        let client = ExampleAPIClient(session: Replay.session)
        _ = try await client.fetchUser(id: 42)
    }

    @Test(.replay("fetchPosts", matching: [.method, .path], scope: .test))
    func fetchPosts() async throws {
        // Each test gets its own isolated playback store
        let client = ExampleAPIClient(session: Replay.session)
        _ = try await client.fetchPosts()
    }
}
```

**Key differences with `scope: .test`:**

| Aspect          | `scope: .global` (default)      | `scope: .test`            |
| --------------- | ------------------------------- | ------------------------- |
| Execution       | Serialized (one test at a time) | Parallel                  |
| URLSession      | Works with `URLSession.shared`  | Requires `Replay.session` |
| State isolation | Shared global state             | Per-test isolated state   |

> [!IMPORTANT]
> When using `scope: .test`, you must use `Replay.session` (or `Replay.makeSession()`)
> instead of `URLSession.shared`. The test-scoped playback store is routed via a custom
> HTTP header that only `Replay.session` includes.

### Multiple requests per test

Each HAR file can contain multiple request/response entries.
Use one archive per test—don't stack `.replay(...)` traits:

```swift
@Test(.replay("fetchUser"), .replay("fetchPosts")) // ❌ Don't do this
func myTest() async throws { /* ... */ }
```

If a test makes multiple requests,
record them all into a single HAR file.

### Creating HAR files from browser sessions

You can also capture traffic using browser developer tools.
Open the Network tab, trigger the requests, then export as HAR:

- **Safari**: Right-click → Export HAR
- **Chrome**: Click ↓ → Save all as HAR with content
- **Firefox**: Right-click → Save All As HAR

> [!WARNING]
> Browser-exported HAR files often contain sensitive data (cookies, tokens, PII).
> Always review and redact before committing.

### Using Replay without Swift Testing

For XCTest or manual control, use the lower-level APIs directly:

```swift
// Playback from a HAR file
let config = PlaybackConfiguration(
    source: .file(archiveURL),
    playbackMode: .strict,  // or .passthrough, .live
    recordMode: .none,      // or .once, .rewrite
    matchers: [.method, .path]
)
let session = try await Playback.session(configuration: config)

// Record traffic
let captureConfig = CaptureConfiguration(destination: .file(archiveURL))
let recordingSession = try await Capture.session(configuration: captureConfig)

// Read/write HAR files directly
let archive = try HAR.load(from: archiveURL)
try HAR.save(archive, to: outputURL)
```

## Tooling

Replay includes a Swift Package Manager command plugin to help manage HAR archives.

```bash
# Check status of archives (age, orphans, etc.)
swift package replay status

# Record specific tests (runs `swift test --filter …` with `REPLAY_RECORD_MODE=once` or `rewrite`)
swift package replay record ExampleAPITests.fetchUser

# Note: The archive name and location come from your `@Test(.replay("…"))`
# configuration (or the auto-generated name),
# not from the `--filter` string passed to the `swift test` command.

# Inspect a HAR file
swift package replay inspect Tests/YourTests/Replays/fetchUser.har

# Validate a HAR file
swift package replay validate Tests/YourTests/Replays/fetchUser.har

# Filter sensitive data from an existing HAR
swift package replay filter input.har output.har --headers Authorization --query-params token
```

> [!NOTE]
> Add `--allow-writing-to-package-directory` to commands to skip confirmation step.

## Troubleshooting

### “Replay Archive Missing”

This is expected on first run (unless you've already created `Replays/<name>.har`).
Record intentionally for the failing test:

```bash
REPLAY_RECORD_MODE=rewrite swift test --filter <your-test-name>
```

### “No Matching Entry in Archive”

This means the test made a request that didn't match any entry in the HAR.
Common fixes:

- Use a more stable matcher set (often `.method, .path` instead of full `.url`)
- Re-record the fixture intentionally
- Inspect the archive to see what it contains:

```bash
swift package replay inspect path/to/archive.har
```

## License

This project is available under the MIT license.
See the LICENSE file for more info.
