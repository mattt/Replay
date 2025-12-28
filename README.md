# Replay

> [!CAUTION]
> This package is in active development, and may make breaking changes before an initial release.

HTTP recording, playback, and stubbing for Swift,
built around <abbr title="HTTP Archive">HAR</abbr> fixtures 
and Swift Testing traits.

## Requirements

- Swift 6.1+
- macOS 14+ / iOS 17+ / tvOS 17+ / watchOS 10+ / visionOS 1+

## Installation

### Swift Package Manager

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
ensure they're included as test resources (see the tutorial below).

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

@Test(.replay("fetchUser"))
func fetchUser() async throws {
    let (data, _) = try await URLSession.shared.data(
        from: URL(string: "https://api.example.com/users/42")!
    )
    let user = try JSONDecoder().decode(User.self, from: data)
    #expect(user.id == 42)
}
```

Replay can also run **without** a HAR file by using in-memory stubs:

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
    let (data, _) = try await URLSession.shared.data(
        from: URL(string: "https://example.com/greeting")!
    )
    #expect(String(data: data, encoding: .utf8) == "Hello, world!")
}
```

<details>
<summary><code>fetchUser.har</code> contents</summary>

```json
{
  "log": {
    "version": "1.2",
    "creator": {
      "name": "Replay",
      "version": "1.0"
    },
    "entries": [
      {
        "startedDateTime": "2024-01-15T10:30:00.000Z",
        "time": 150,
        "request": {
          "method": "GET",
          "url": "https://api.example.com/users/42",
          "httpVersion": "HTTP/1.1",
          "cookies": [],
          "headers": [
            { "name": "Accept", "value": "application/json" }
          ],
          "queryString": [],
          "headersSize": -1,
          "bodySize": 0
        },
        "response": {
          "status": 200,
          "statusText": "OK",
          "httpVersion": "HTTP/1.1",
          "cookies": [],
          "headers": [
            { "name": "Content-Type", "value": "application/json" }
          ],
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

## Getting Started

Let's walk through a simple end-to-end setup.

### 0) Design your HTTP client to accept a session (optional but recommended)

Replay _can_ intercept `URLSession.shared` globally, 
but making it so that your API client accepts a `URLSession` parameter 
makes it easy to opt into `.test` scope later 
(and it's generally good design).

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

### 1) Add a `Replays/` folder to your test target

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

### 2) Write a test using `.replay("…")`

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

### 3) Run tests (playback-only by default)

The first run should fail if `Replays/fetchUser.har` doesn't exist yet.
That's expected — Replay is designed to prevent accidental “record-on-first-run”.

```console
swift test
❌  Test fetchUser() recorded an issue at ExampleTests.swift
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  No Matching Entry in Archive
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Request: GET https://api.example.com/users/42
Archive: /path/to/.../Replays/fetchUser.har

This request was not found in the replay archive.

Options:
1. Run against the live network (skip replay + no recording):
   REPLAY_MODE=live swift test --filter <test-name>

2. Update the archive with new requests:
   REPLAY_MODE=record swift test --filter <test-name>

3. Check if request details changed (URL, method, headers)
   and update test expectations

4. Inspect the archive:
   swift package replay inspect /path/to/.../Replays/fetchUser.har

```

### 4) Record intentionally

Enable recording for a single test (recommended), or an entire suite:

```bash
# Record one test
REPLAY_MODE=record swift test --filter YourSuite.fetchUser
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
> - **No fixture required**: missing `Replays/*.har` won't fail the test.
> - **No fixture writes**: nothing is recorded or modified.

### 5) Re-run (back to playback-only)

```console
swift test
✅  Test fetchUser() passed after 0.001 seconds.
```

### 6) Commit fixtures safely

> [!WARNING]
> HAR files may contain sensitive data (cookies, auth headers, tokens, PII).
> Always review/redact before committing to source control.

Replay can redact while recording using filters (recommended) 
or you can filter an existing HAR file using the plugin (see Tooling).

## Common patterns and recipes

### Use matching strategies to make fixtures stable

By default, replay fixtures are matched by HTTP method + full URL (including query).
That's great for fully deterministic endpoints,
but many APIs have volatile query items
(pagination cursors, timestamps, cache-busters).

In those cases, you can configure to match on just HTTP method and URL path (ignoring query):

```swift
@Test(.replay("fetchUser", matching: [.method, .path]))
func fetchUser() async throws { /* ... */ }
```

Available matchers:
- `.method`
- `.host`
- `.path`
- `.query`
- `.url` (full absolute URL including query)
- `.headers([String])`
- `.body`
- `.custom((URLRequest, URLRequest) -> Bool)`

### Use filters to remove sensitive and unnecessary

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

### Use stubs to mock requests without an HAR file

Sometimes it's easier to use explicit stub instead of a fixture file.

```swift
import Testing
import Replay

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

### Use `.test` scope + `Replay.session` to run tests in parallel

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

### Use multiple replays in a test

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

Don't stack multiple `.replay(...)` traits on the same test. 
Treat Replay as **one active configuration per test scope**:

```swift
@Test(.replay("fetchUser"), .replay("fetchPosts")) // ❌ Don't do this
func myTest() async throws { /* ... */ }
```

If you need a single test to cover multiple calls, 
you usually have two practical options:

- **Option A** (recommended): 
  record those calls into **one HAR file** 
  (one archive can contain many request/response entries).
- **Option B**: 
  split the scenario into multiple tests, 
  each with its own `@Test(.replay("…"))`.

### Create HAR files from browser sessions

Sometimes it's easier to capture HTTP traffic using your browser's developer tools rather than recording through tests.
All major browsers can export network activity as HAR files.

> [!WARNING]
> HAR files may contain sensitive data including cookies, authentication tokens, passwords, and personal information.
> Always review and redact sensitive data before committing HAR files to version control.

#### Safari

1. Enable the Develop menu: **Safari → Settings → Advanced → Show features for web developers**
2. Open Developer Tools: **Develop → Show Web Inspector** (or <kbd>⌥⌘I</kbd>)
3. Select the **Network** tab
4. Trigger the API calls you want to capture
5. Right-click in the network list and choose **Export HAR**

#### Chrome

1. Open Developer Tools: **View → Developer → Developer Tools** (or <kbd>⌥⌘I</kbd>)
2. Select the **Network** tab
3. Trigger the API calls you want to capture
4. Click the **↓** (download) button and choose **Save all as HAR with content**

#### Firefox

1. Open Developer Tools: **Tools → Browser Tools → Web Developer Tools** (or <kbd>⌥⌘I</kbd>)
2. Select the **Network** tab
3. Trigger the API calls you want to capture
4. Right-click in the network list and choose **Save All As HAR**

### Use Replay without Swift Testing

If you're not using Swift Testing (or you want explicit control),
use the lower-level APIs:

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
> Add `--allow-writing-to-package-directory` to commands to skip confirmation step.

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

This is expected on first run (unless you've already created `Replays/<name>.har`).
Record intentionally for the failing test:

```bash
REPLAY_MODE=record swift test --filter <your-test-name>
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
