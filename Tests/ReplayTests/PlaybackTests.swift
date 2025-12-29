import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("Playback Tests", .serialized)
struct PlaybackTests {
    private final class NetworkStubURLProtocol: URLProtocol {
        // Test-only shared state.
        // Safe here because the enclosing suite is `.serialized` and access is deterministic.
        nonisolated(unsafe) static var response: (status: Int, body: Data) = (200, Data())

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "network-stub.example"
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            let stub = Self.response
            let headers = ["Content-Type": "text/plain"]
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: stub.status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!

            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    // MARK: - ReplayScope Tests

    @Suite("ReplayScope Tests")
    struct ReplayScopeTests {
        @Test("global scope exists")
        func globalScope() {
            let scope: ReplayScope = .global
            #expect(scope == .global)
        }

        @Test("test scope exists")
        func testScope() {
            let scope: ReplayScope = .test
            #expect(scope == .test)
        }

        @Test("scopes are Sendable")
        func sendable() async {
            let scope: ReplayScope = .test
            await Task.detached {
                _ = scope
            }.value
        }
    }

    // MARK: - PlaybackConfiguration.Source Tests

    @Suite("PlaybackConfiguration.Source Tests")
    struct SourceTests {
        @Test("file source holds URL")
        func fileSource() {
            let url = URL(fileURLWithPath: "/tmp/test.har")
            let source: PlaybackConfiguration.Source = .file(url)

            if case .file(let storedURL) = source {
                #expect(storedURL == url)
            } else {
                Issue.record("Expected .file source")
            }
        }

        @Test("entries source holds HAR.Entry array")
        func entriesSource() {
            let entries = [makeTestEntry()]
            let source: PlaybackConfiguration.Source = .entries(entries)

            if case .entries(let storedEntries) = source {
                #expect(storedEntries.count == 1)
            } else {
                Issue.record("Expected .entries source")
            }
        }

        @Test("stubs source holds Stub array")
        func stubsSource() {
            let stubs: [Stub] = [.get("https://example.com", 200, ["Content-Type": "text/plain"], { "Success" })]
            let source: PlaybackConfiguration.Source = .stubs(stubs)

            if case .stubs(let storedStubs) = source {
                #expect(storedStubs.count == 1)
            } else {
                Issue.record("Expected .stubs source")
            }
        }
    }

    // MARK: - PlaybackConfiguration Tests

    @Suite("PlaybackConfiguration Tests")
    struct ConfigurationTests {
        @Test("initializes with source only")
        func initWithSourceOnly() {
            let stubs: [Stub] = [.get("https://example.com", 200, ["Content-Type": "text/plain"], { "Success" })]
            let config = PlaybackConfiguration(source: .stubs(stubs))

            if case .stubs = config.source {
                #expect(Bool(true))
            } else {
                Issue.record("Expected .stubs source")
            }
            #expect(config.playbackMode == .strict)
            #expect(config.recordMode == .none)
            #expect(config.matchers.isEmpty == false)
            #expect(config.filters.isEmpty)
        }

        @Test("initializes with all parameters")
        func initWithAllParameters() {
            let config = PlaybackConfiguration(
                source: .entries([makeTestEntry()]),
                playbackMode: .passthrough,
                recordMode: .none,
                matchers: [],
                filters: []
            )

            if case .entries = config.source {
                #expect(Bool(true))
            } else {
                Issue.record("Expected .entries source")
            }
            #expect(config.playbackMode == .passthrough)
            #expect(config.recordMode == .none)
            #expect(config.matchers.isEmpty)
            #expect(config.filters.isEmpty)
        }

        @Test("configuration is Sendable")
        func sendable() async {
            let config = PlaybackConfiguration(
                source: .stubs([.get("https://example.com", 200, ["Content-Type": "text/plain"], { "Success" })]),
                playbackMode: .strict,
                recordMode: .none
            )

            await Task.detached {
                _ = config.playbackMode
            }.value
        }
    }

    // MARK: - PlaybackStore Tests

    @Suite("PlaybackStore Tests")
    struct PlaybackStoreTests {
        @Test("shared instance exists")
        func sharedInstance() async {
            _ = PlaybackStore.shared
        }

        @Test("configure with stubs populates entries")
        func configureWithStubs() async throws {
            let store = PlaybackStore()
            let stubs: [Stub] = [
                .get("https://example.com/api", 200, ["Content-Type": "text/plain"]) { "OK" },
                .post("https://example.com/users", 201, ["Content-Type": "text/plain"]) { "Created" },
                .put("https://example.com/users/1", 200, ["Content-Type": "text/plain"]) { "Updated" },
                .delete("https://example.com/users/1", 204, ["Content-Type": "text/plain"]) { "Deleted" },
                .patch("https://example.com/users/1", 200, ["Content-Type": "text/plain"]) { "Patched" },
                .head("https://example.com/users/1", 200, ["Content-Type": "text/plain"]),
                .options("https://example.com/users/1", 200, ["Content-Type": "text/plain"]),
                .trace("https://example.com/users/1", 200, ["Content-Type": "text/plain"]),
                .connect("https://example.com/users/1", 200, ["Content-Type": "text/plain"]),
                Stub(
                    .custom("SYNC"),
                    URL(string: "https://example.com/users")!,
                    status: 200,
                    headers: ["Content-Type": "text/plain"],
                    body: "Sync"
                ),
            ]

            try await store.configure(PlaybackConfiguration(source: .stubs(stubs)))
            let entries = await store.getAvailableEntries()

            #expect(entries.count == stubs.count)
            #expect(entries[0].request.url == "https://example.com/api")
            #expect(entries[0].response.status == 200)
            #expect(entries[0].response.headers.contains { $0.name == "Content-Type" && $0.value == "text/plain" })
        }

        @Test("configure with entries populates entries")
        func configureWithEntries() async throws {
            let store = PlaybackStore()
            let entries = [makeTestEntry(), makeTestEntry()]

            try await store.configure(PlaybackConfiguration(source: .entries(entries)))
            let storedEntries = await store.getAvailableEntries()

            #expect(storedEntries.count == 2)
        }

        @Test("configure with log populates entries")
        func configureWithLog_populatesEntries_removedCase() async throws {
            // `.log` was removed pre-1.0; use `.entries(log.entries)` instead.
            let store = PlaybackStore()
            let entry = makeTestEntry()
            try await store.configure(PlaybackConfiguration(source: .entries([entry])))
            let entries = await store.getAvailableEntries()
            #expect(entries.count == 1)
        }

        @Test("configure with missing file throws in strict mode")
        func configureWithMissingFileStrictThrows() async {
            let store = PlaybackStore()
            let url = URL(fileURLWithPath: "/tmp/replay-missing-\(UUID().uuidString).har")

            await #expect(throws: Error.self) {
                try await store.configure(
                    PlaybackConfiguration(
                        source: .file(url),
                        playbackMode: .strict,
                        recordMode: .none
                    )
                )
            }
        }

        @Test("configure with missing file succeeds when recording is enabled")
        func configureWithMissingFileRecordingSucceeds() async throws {
            let store = PlaybackStore()
            let url = URL(fileURLWithPath: "/tmp/replay-missing-\(UUID().uuidString).har")

            try await store.configure(
                PlaybackConfiguration(
                    source: .file(url),
                    playbackMode: .strict,
                    recordMode: .once
                )
            )
            #expect(await store.getAvailableEntries().isEmpty)
        }

        @Test("getAvailableEntries returns configured entries")
        func getAvailableEntries() async throws {
            let store = PlaybackStore()
            let stubs: [Stub] = [.get("https://example.com", 200, ["Content-Type": "text/plain"], { "Test" })]

            try await store.configure(PlaybackConfiguration(source: .stubs(stubs)))
            let entries = await store.getAvailableEntries()

            #expect(entries.count == 1)
            #expect(entries[0].request.url == "https://example.com")
        }

        @Test("handleRequest returns matching entry response")
        func handleRequestMatching() async throws {
            let store = PlaybackStore()
            let url = URL(string: "https://example.com/test")!
            let stubs: [Stub] = [.get(url.absoluteString, 200, ["Content-Type": "text/plain"], { "Success" })]

            try await store.configure(PlaybackConfiguration(source: .stubs(stubs)))

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (response, data) = try await store.handleRequest(request)

            #expect(response.statusCode == 200)
            #expect(String(data: data, encoding: .utf8) == "Success")
        }

        @Test("handleRequest throws when not configured")
        func handleRequestNotConfigured() async throws {
            let store = PlaybackStore()
            let request = URLRequest(url: URL(string: "https://example.com")!)

            await #expect(throws: ReplayError.self) {
                try await store.handleRequest(request)
            }
        }

        @Test("handleRequest throws in strict mode when no match")
        func handleRequestStrictNoMatch() async throws {
            let store = PlaybackStore()
            let stubs: [Stub] = [.get("https://example.com/api", 200, ["Content-Type": "text/plain"], { "Success" })]

            try await store.configure(
                PlaybackConfiguration(
                    source: .stubs(stubs),
                    playbackMode: .strict,
                    recordMode: .none
                )
            )

            let request = URLRequest(url: URL(string: "https://different.com")!)

            await #expect(throws: ReplayError.self) {
                try await store.handleRequest(request)
            }
        }

        @Test("clear resets store state")
        func clearResetsState() async throws {
            let store = PlaybackStore()
            let stubs: [Stub] = [.get("https://example.com", 200, ["Content-Type": "text/plain"], { "Success" })]

            try await store.configure(PlaybackConfiguration(source: .stubs(stubs)))
            #expect(await store.getAvailableEntries().count == 1)

            await store.clear()
            #expect(await store.getAvailableEntries().isEmpty)
        }

        @Test("clear allows reconfiguration")
        func clearAllowsReconfiguration() async throws {
            let store = PlaybackStore()

            try await store.configure(
                PlaybackConfiguration(
                    source: .stubs([.get("https://first.com", 200, ["Content-Type": "text/plain"], { "Success" })]))
            )
            #expect(await store.getAvailableEntries().count == 1)

            await store.clear()

            try await store.configure(
                PlaybackConfiguration(
                    source: .stubs([
                        .get("https://second.com", 200, ["Content-Type": "text/plain"], { "Success" }),
                        .get("https://third.com", 200, ["Content-Type": "text/plain"], { "Success" }),
                    ])
                )
            )
            #expect(await store.getAvailableEntries().count == 2)
        }
    }

    // MARK: - PlaybackStoreRegistry Tests

    @Suite("PlaybackStoreRegistry Tests")
    struct PlaybackStoreRegistryTests {
        @Test("shared instance exists")
        func sharedInstance() {
            _ = PlaybackStoreRegistry.shared
        }

        @Test("register returns stable key")
        func registerReturnsStableKey() {
            let registry = PlaybackStoreRegistry()
            let store = PlaybackStore()

            let key1 = registry.register(store)
            let key2 = registry.register(store)

            #expect(key1 == key2)
        }

        @Test("register returns unique keys for different stores")
        func registerReturnsUniqueKeys() {
            let registry = PlaybackStoreRegistry()
            let store1 = PlaybackStore()
            let store2 = PlaybackStore()

            let key1 = registry.register(store1)
            let key2 = registry.register(store2)

            #expect(key1 != key2)
        }

        @Test("store(for:) returns registered store")
        func storeForReturnsRegistered() {
            let registry = PlaybackStoreRegistry()
            let store = PlaybackStore()

            let key = registry.register(store)
            let retrieved = registry.store(for: key)

            #expect(retrieved != nil)
        }

        @Test("store(for:) returns nil for unknown key")
        func storeForReturnsNilForUnknown() {
            let registry = PlaybackStoreRegistry()

            let retrieved = registry.store(for: "unknown-key")

            #expect(retrieved == nil)
        }

        @Test("unregister removes store")
        func unregisterRemovesStore() {
            let registry = PlaybackStoreRegistry()
            let store = PlaybackStore()

            let key = registry.register(store)
            #expect(registry.store(for: key) != nil)

            registry.unregister(key: key)
            #expect(registry.store(for: key) == nil)
        }

        @Test("unregister with unknown key does not crash")
        func unregisterUnknownKey() {
            let registry = PlaybackStoreRegistry()

            registry.unregister(key: "nonexistent")
        }

        @Test("key(for:) generates consistent key")
        func keyForGeneratesConsistentKey() {
            let store = PlaybackStore()

            let key1 = PlaybackStoreRegistry.key(for: store)
            let key2 = PlaybackStoreRegistry.key(for: store)

            #expect(key1 == key2)
        }

        @Test("concurrent register and unregister is thread-safe")
        func concurrentAccess() async {
            let registry = PlaybackStoreRegistry()
            let stores = (0 ..< 10).map { _ in PlaybackStore() }

            await withTaskGroup(of: Void.self) { group in
                for store in stores {
                    group.addTask {
                        let key = registry.register(store)
                        _ = registry.store(for: key)
                        registry.unregister(key: key)
                    }
                }
            }
        }
    }

    // MARK: - Playback Enum Tests

    @Suite("Playback Tests")
    struct PlaybackEnumTests {
        @Test("session creates URLSession with playback configuration")
        func sessionCreatesURLSession() async throws {
            let stubs: [Stub] = [.get("https://example.com", 200, ["Content-Type": "text/plain"], { "Stubbed" })]

            let session = try await Playback.session(
                configuration: PlaybackConfiguration(source: .stubs(stubs))
            )

            #expect(session.configuration.protocolClasses?.contains { $0 == PlaybackURLProtocol.self } == true)
        }

        @Test("session configures protocol classes")
        func sessionConfiguresProtocolClasses() async throws {
            let stubs: [Stub] = [.get("https://example.com", 200, ["Content-Type": "text/plain"], { "Success" })]

            let session = try await Playback.session(
                configuration: PlaybackConfiguration(source: .stubs(stubs))
            )

            #expect(session.configuration.protocolClasses?.first == PlaybackURLProtocol.self)
        }

        @Test("session accepts custom base configuration")
        func sessionAcceptsCustomBaseConfiguration() async throws {
            let stubs: [Stub] = [.get("https://example.com", 200, ["Content-Type": "text/plain"], { "Success" })]
            let baseConfig = URLSessionConfiguration.default
            baseConfig.timeoutIntervalForRequest = 999

            let session = try await Playback.session(
                configuration: PlaybackConfiguration(source: .stubs(stubs)),
                baseConfiguration: baseConfig
            )

            #expect(session.configuration.timeoutIntervalForRequest == 999)
        }

        @Test("clear resets store state")
        func clearResetsStoreState() async throws {
            let store = PlaybackStore()
            let stubs: [Stub] = [.get("https://example.com", 200, ["Content-Type": "text/plain"], { "Success" })]

            try await store.configure(PlaybackConfiguration(source: .stubs(stubs)))
            let entriesBefore = await store.getAvailableEntries()
            #expect(entriesBefore.count == 1)

            await store.clear()

            let entriesAfter = await store.getAvailableEntries()
            #expect(entriesAfter.isEmpty)
        }
    }

    // MARK: - PlaybackURLProtocol Tests

    @Suite("PlaybackURLProtocol Tests")
    struct PlaybackURLProtocolTests {
        @Test("canInit returns true for unhandled requests")
        func canInitForUnhandledRequests() {
            let request = URLRequest(url: URL(string: "https://example.com")!)

            let result = PlaybackURLProtocol.canInit(with: request)

            #expect(result == true)
        }

        @Test("canonicalRequest returns same request")
        func canonicalRequestReturnsSame() {
            let request = URLRequest(url: URL(string: "https://example.com")!)

            let canonical = PlaybackURLProtocol.canonicalRequest(for: request)

            #expect(canonical.url == request.url)
        }
    }

    // MARK: - Store HandleRequest Tests

    @Suite("PlaybackStore handleRequest Tests")
    struct StoreHandleRequestTests {
        @Test("stub-based store returns correct response")
        func stubBasedStore() async throws {
            let store = PlaybackStore()
            let url = URL(string: "https://api.example.com/data")!
            let stubs: [Stub] = [
                .get(
                    url.absoluteString, 200, ["Content-Type": "application/json"],
                    { "{\"success\":true}" }
                )
            ]

            try await store.configure(PlaybackConfiguration(source: .stubs(stubs)))

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (response, data) = try await store.handleRequest(request)

            #expect(response.statusCode == 200)
            #expect(String(data: data, encoding: .utf8) == "{\"success\":true}")
        }

        @Test("entry-based store returns correct response")
        func entryBasedStore() async throws {
            let store = PlaybackStore()
            let url: URL = URL(string: "https://api.example.com/users")!
            let entry = makeTestEntryFor(url: url, status: 201, body: "Created")

            try await store.configure(PlaybackConfiguration(source: .entries([entry])))

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (response, data) = try await store.handleRequest(request)

            #expect(response.statusCode == 201)
            #expect(String(data: data, encoding: .utf8) == "Created")
        }

        @Test("entries-based store returns correct response (from log entries)")
        func entriesBasedStore_fromLogEntries() async throws {
            let store = PlaybackStore()
            let url = URL(string: "https://api.example.com/status")!
            var log = HAR.create()
            log.entries = [makeTestEntryFor(url: url, status: 204, body: "")]

            try await store.configure(PlaybackConfiguration(source: .entries(log.entries)))

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (response, _) = try await store.handleRequest(request)

            #expect(response.statusCode == 204)
        }

        @Test("live mode ignores recorded entries and always hits the network")
        func liveModeIgnoresEntries() async throws {
            URLProtocol.registerClass(NetworkStubURLProtocol.self)
            defer { URLProtocol.unregisterClass(NetworkStubURLProtocol.self) }

            NetworkStubURLProtocol.response = (status: 204, body: Data())

            let store = PlaybackStore()
            let url = URL(string: "https://network-stub.example/status")!
            let matchingEntry = makeTestEntryFor(url: url, status: 200, body: "fixture")

            try await store.configure(
                PlaybackConfiguration(
                    source: .entries([matchingEntry]),
                    playbackMode: .live,
                    recordMode: .none
                )
            )

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (response, _) = try await store.handleRequest(request)
            #expect(response.statusCode == 204)  // from NetworkStubURLProtocol, not fixture
        }

        @Test("multiple stubs match by URL")
        func multipleStubsMatchByURL() async throws {
            let store = PlaybackStore()
            let url1 = URL(string: "https://api.example.com/first")!
            let url2 = URL(string: "https://api.example.com/second")!
            let stubs: [Stub] = [
                .get(url1.absoluteString, 200, ["Content-Type": "text/plain"], { "First" }),
                .get(url2.absoluteString, 200, ["Content-Type": "text/plain"], { "Second" }),
            ]

            try await store.configure(PlaybackConfiguration(source: .stubs(stubs)))

            var request1 = URLRequest(url: url1)
            request1.httpMethod = "GET"
            var request2 = URLRequest(url: url2)
            request2.httpMethod = "GET"

            let (_, data1) = try await store.handleRequest(request1)
            let (_, data2) = try await store.handleRequest(request2)

            #expect(String(data: data1, encoding: .utf8) == "First")
            #expect(String(data: data2, encoding: .utf8) == "Second")
        }

        @Test("strict mode throws for unmatched requests")
        func strictModeThrowsForUnmatched() async throws {
            let store = PlaybackStore()
            let stubs: [Stub] = [.get("https://expected.com", 200, ["Content-Type": "text/plain"], { "Success" })]

            try await store.configure(
                PlaybackConfiguration(
                    source: .stubs(stubs),
                    playbackMode: .strict,
                    recordMode: .none
                )
            )

            let request = URLRequest(url: URL(string: "https://unexpected.com")!)

            await #expect(throws: ReplayError.self) {
                _ = try await store.handleRequest(request)
            }
        }
    }
}

// MARK: - Test Helpers

private func makeTestRequest() -> HAR.Request {
    HAR.Request(
        method: "GET",
        url: "https://example.com/api",
        httpVersion: "HTTP/1.1",
        headers: [HAR.Header(name: "Accept", value: "application/json")],
        bodySize: 0
    )
}

private func makeTestResponse() -> HAR.Response {
    let content = HAR.Content(size: 2, mimeType: "text/plain", text: "OK")
    return HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: 2
    )
}

private func makeTestEntry() -> HAR.Entry {
    HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: makeTestRequest(),
        response: makeTestResponse(),
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}

private func makeTestEntryFor(url: URL, status: Int, body: String) -> HAR.Entry {
    let request = HAR.Request(
        method: "GET",
        url: url.absoluteString,
        httpVersion: "HTTP/1.1",
        headers: [],
        bodySize: 0
    )
    let content = HAR.Content(size: body.count, mimeType: "text/plain", text: body)
    let response = HAR.Response(
        status: status,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: body.count
    )
    return HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: request,
        response: response,
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}
