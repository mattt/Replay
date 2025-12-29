import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

// MARK: - Lock-Isolated Helper for Thread-Safe Test State

final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func setValue(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}

@Suite("Capture Tests", .serialized)
struct CaptureTests {

    // MARK: - CaptureConfiguration Tests

    @Suite("CaptureConfiguration Tests")
    struct CaptureConfigurationTests {

        @Test("initializes with file destination")
        func initWithFileDestination() {
            let url = URL(fileURLWithPath: "/tmp/test.har")
            let config = CaptureConfiguration(destination: .file(url))

            if case .file(let configURL) = config.destination {
                #expect(configURL == url)
            } else {
                Issue.record("Expected file destination")
            }
            #expect(config.filters.isEmpty)
            #expect(config.matchers == nil)
        }

        @Test("initializes with memory destination")
        func initWithMemoryDestination() {
            let config = CaptureConfiguration(destination: .memory)

            if case .memory = config.destination {
                // Success
            } else {
                Issue.record("Expected memory destination")
            }
            #expect(config.filters.isEmpty)
            #expect(config.matchers == nil)
        }

        @Test("initializes with handler destination")
        func initWithHandlerDestination() async {
            let capturedEntry = LockIsolated<HAR.Entry?>(nil)
            let config = CaptureConfiguration(
                destination: .handler { entry in
                    capturedEntry.setValue(entry)
                }
            )

            if case .handler(let handler) = config.destination {
                let testEntry = makeTestEntry()
                await handler(testEntry)
                #expect(capturedEntry.value != nil)
                #expect(capturedEntry.value?.request.url == testEntry.request.url)
            } else {
                Issue.record("Expected handler destination")
            }
        }

        @Test("initializes with filters")
        func initWithFilters() {
            let filter = Filter.headers(removing: ["Authorization"])
            let config = CaptureConfiguration(
                destination: .memory,
                filters: [filter]
            )

            #expect(config.filters.count == 1)
        }

        @Test("initializes with matchers")
        func initWithMatchers() {
            let matcher = Matcher.host
            let config = CaptureConfiguration(
                destination: .memory,
                matchers: [matcher]
            )

            #expect(config.matchers?.count == 1)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let url = URL(fileURLWithPath: "/tmp/test.har")
            let filter = Filter.headers(removing: ["Cookie"])
            let matcher = Matcher.host

            let config = CaptureConfiguration(
                destination: .file(url),
                filters: [filter],
                matchers: [matcher]
            )

            if case .file(let configURL) = config.destination {
                #expect(configURL == url)
            } else {
                Issue.record("Expected file destination")
            }
            #expect(config.filters.count == 1)
            #expect(config.matchers?.count == 1)
        }
    }

    // MARK: - CaptureStore Tests

    @Suite("CaptureStore Tests")
    struct CaptureStoreTests {

        @Test("configure sets configuration")
        func configureSetConfiguration() async {
            let store = CaptureStore()
            let config = CaptureConfiguration(destination: .memory)

            await store.configure(config)

            let currentConfig = await store.currentConfiguration
            #expect(currentConfig != nil)
        }

        @Test("configure clears existing entries")
        func configureClearsEntries() async {
            let store = CaptureStore()
            let config = CaptureConfiguration(destination: .memory)

            await store.configure(config)
            await store.store(makeTestEntry())

            let entriesBefore = await store.getEntries()
            #expect(entriesBefore.count == 1)

            await store.configure(config)

            let entriesAfter = await store.getEntries()
            #expect(entriesAfter.isEmpty)
        }

        @Test("store adds entry to memory destination")
        func storeAddsEntryToMemory() async {
            let store = CaptureStore()
            let config = CaptureConfiguration(destination: .memory)

            await store.configure(config)
            await store.store(makeTestEntry())

            let entries = await store.getEntries()
            #expect(entries.count == 1)
        }

        @Test("store calls handler for handler destination")
        func storeCallsHandler() async {
            let store = CaptureStore()
            let handlerCalled = LockIsolated(false)
            let capturedEntry = LockIsolated<HAR.Entry?>(nil)

            let config = CaptureConfiguration(
                destination: .handler { entry in
                    handlerCalled.setValue(true)
                    capturedEntry.setValue(entry)
                }
            )

            await store.configure(config)
            let testEntry = makeTestEntry()
            await store.store(testEntry)

            #expect(handlerCalled.value)
            #expect(capturedEntry.value?.request.url == testEntry.request.url)
        }

        @Test("store saves to file for file destination")
        func storeSavesToFile() async throws {
            let store = CaptureStore()
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("CaptureTests_store.har")

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            let config = CaptureConfiguration(destination: .file(tempURL))
            await store.configure(config)
            await store.store(makeTestEntry())

            #expect(FileManager.default.fileExists(atPath: tempURL.path))

            let loaded = try HAR.load(from: tempURL)
            #expect(loaded.entries.count == 1)
        }

        @Test("getEntries returns all stored entries")
        func getEntriesReturnsAll() async {
            let store = CaptureStore()
            let config = CaptureConfiguration(destination: .memory)

            await store.configure(config)
            await store.store(makeTestEntry(url: "https://example.com/1"))
            await store.store(makeTestEntry(url: "https://example.com/2"))
            await store.store(makeTestEntry(url: "https://example.com/3"))

            let entries = await store.getEntries()
            #expect(entries.count == 3)
        }

        @Test("clear removes all entries and configuration")
        func clearRemovesAll() async {
            let store = CaptureStore()
            let config = CaptureConfiguration(destination: .memory)

            await store.configure(config)
            await store.store(makeTestEntry())

            await store.clear()

            let entries = await store.getEntries()
            let currentConfig = await store.currentConfiguration

            #expect(entries.isEmpty)
            #expect(currentConfig == nil)
        }

        @Test("recordEntry creates and stores HAR entry")
        func recordEntryCreatesAndStores() async throws {
            let store = CaptureStore()
            let config = CaptureConfiguration(destination: .memory)
            await store.configure(config)

            let url = URL(string: "https://example.com/api/test")!
            let request = URLRequest(url: url)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = "{\"success\":true}".data(using: .utf8)!

            await store.recordEntry(
                request: request,
                response: response,
                data: data,
                startTime: Date(),
                duration: 0.1
            )

            let entries = await store.getEntries()
            #expect(entries.count == 1)
            #expect(entries[0].request.url == "https://example.com/api/test")
            #expect(entries[0].response.status == 200)
        }

        @Test("recordEntry applies filters")
        func recordEntryAppliesFilters() async throws {
            let store = CaptureStore()
            let filter = Filter.headers(removing: ["Authorization"])
            let config = CaptureConfiguration(destination: .memory, filters: [filter])
            await store.configure(config)

            let url = URL(string: "https://example.com/api")!
            var request = URLRequest(url: url)
            request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            await store.recordEntry(
                request: request,
                response: response,
                data: Data(),
                startTime: Date(),
                duration: 0.05
            )

            let entries = await store.getEntries()
            #expect(entries.count == 1)

            let authHeader = entries[0].request.headers.first { $0.name == "Authorization" }
            #expect(authHeader?.value == "[FILTERED]")
        }

        @Test("recordEntry respects matchers")
        func recordEntryRespectsMatchers() async throws {
            let store = CaptureStore()
            let matcher = Matcher.custom { request, _ in
                request.url?.host?.hasSuffix("example.com") == true
            }
            let config = CaptureConfiguration(destination: .memory, matchers: [matcher])
            await store.configure(config)

            let matchingURL = URL(string: "https://api.example.com/test")!
            let nonMatchingURL = URL(string: "https://other.org/test")!

            let matchingResponse = HTTPURLResponse(
                url: matchingURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            let nonMatchingResponse = HTTPURLResponse(
                url: nonMatchingURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            await store.recordEntry(
                request: URLRequest(url: matchingURL),
                response: matchingResponse,
                data: Data(),
                startTime: Date(),
                duration: 0.05
            )

            await store.recordEntry(
                request: URLRequest(url: nonMatchingURL),
                response: nonMatchingResponse,
                data: Data(),
                startTime: Date(),
                duration: 0.05
            )

            let entries = await store.getEntries()
            #expect(entries.count == 1)
            #expect(entries[0].request.url == "https://api.example.com/test")
        }

        @Test("recordEntry does nothing without configuration")
        func recordEntryWithoutConfig() async {
            let store = CaptureStore()

            let url = URL(string: "https://example.com/api")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            await store.recordEntry(
                request: URLRequest(url: url),
                response: response,
                data: Data(),
                startTime: Date(),
                duration: 0.05
            )

            let entries = await store.getEntries()
            #expect(entries.isEmpty)
        }
    }

    // MARK: - Capture Static Methods Tests

    @Suite("Capture Static Methods Tests")
    struct CaptureStaticMethodsTests {

        @Test("session creates URLSession with CaptureURLProtocol")
        func sessionCreatesURLSession() async {
            let config = CaptureConfiguration(destination: .memory)
            let session = await Capture.session(configuration: config)

            let protocolClasses = session.configuration.protocolClasses ?? []
            let hasCaptureProtocol = protocolClasses.contains { $0 == CaptureURLProtocol.self }

            #expect(hasCaptureProtocol)

            await Capture.clear()
        }

        @Test("session accepts custom base configuration")
        func sessionWithCustomBaseConfig() async {
            let baseConfig = URLSessionConfiguration.ephemeral
            baseConfig.timeoutIntervalForRequest = 30

            let captureConfig = CaptureConfiguration(destination: .memory)
            let session = await Capture.session(
                configuration: captureConfig,
                baseConfiguration: baseConfig
            )

            #expect(session.configuration.timeoutIntervalForRequest == 30)

            await Capture.clear()
        }

        @Test("getEntries returns entries from shared store")
        func getEntriesFromSharedStore() async {
            let config = CaptureConfiguration(destination: .memory)
            await CaptureStore.shared.configure(config)
            await CaptureStore.shared.store(makeTestEntry())

            let entries = await Capture.entries
            #expect(entries.count >= 1)

            await Capture.clear()
        }

        @Test("clear clears shared store")
        func clearClearsSharedStore() async {
            let config = CaptureConfiguration(destination: .memory)
            await CaptureStore.shared.configure(config)
            await CaptureStore.shared.store(makeTestEntry())

            await Capture.clear()

            let entries = await Capture.entries
            #expect(entries.isEmpty)
        }
    }

    // MARK: - CaptureURLProtocol Tests

    @Suite("CaptureURLProtocol Tests")
    struct CaptureURLProtocolTests {

        @Test("canInit returns true for unhandled requests")
        func canInitForUnhandledRequests() {
            let request = URLRequest(url: URL(string: "https://example.com")!)
            #expect(CaptureURLProtocol.canInit(with: request))
        }

        @Test("canInit returns false for already handled requests")
        func canInitReturnsFalseForHandledRequests() {
            let request = URLRequest(url: URL(string: "https://example.com")!)
            let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.setProperty(true, forKey: "ReplayCaptureHandled", in: mutableRequest)

            #expect(!CaptureURLProtocol.canInit(with: mutableRequest as URLRequest))
        }

        @Test("canonicalRequest returns same request")
        func canonicalRequestReturnsSame() {
            let request = URLRequest(url: URL(string: "https://example.com/path")!)
            let canonical = CaptureURLProtocol.canonicalRequest(for: request)

            #expect(canonical.url == request.url)
        }

        @Test("canonicalRequest preserves all request properties")
        func canonicalRequestPreservesProperties() {
            var request = URLRequest(url: URL(string: "https://example.com/path")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = "{}".data(using: .utf8)

            let canonical = CaptureURLProtocol.canonicalRequest(for: request)

            #expect(canonical.httpMethod == "POST")
            #expect(canonical.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(canonical.httpBody == request.httpBody)
        }
    }
}

// MARK: - Test Helpers

private func makeTestRequest(url: String = "https://example.com/api") -> HAR.Request {
    HAR.Request(
        method: "GET",
        url: url,
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

private func makeTestEntry(url: String = "https://example.com/api") -> HAR.Entry {
    HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: makeTestRequest(url: url),
        response: makeTestResponse(),
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}
