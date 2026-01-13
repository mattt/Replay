import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Playback Session Factory

/// Playback APIs for replaying HTTP traffic from recorded sources.
///
/// Use `Playback.session(configuration:baseConfiguration:)` to create a `URLSession`
/// that intercepts requests through `PlaybackURLProtocol`.
public enum Playback {
    /// Create `URLSession` configured for playback using the provided configuration.
    public static func session(
        configuration: PlaybackConfiguration,
        baseConfiguration: URLSessionConfiguration = .ephemeral
    ) async throws -> URLSession {
        let config = baseConfiguration
        var protocols = config.protocolClasses ?? []
        protocols.insert(PlaybackURLProtocol.self, at: 0)
        config.protocolClasses = protocols

        // Prefer isolation: configure a dedicated store and route requests to it via header.
        // This avoids interference when multiple playback sessions exist concurrently.
        let store = PlaybackStore()
        try await store.configure(configuration)
        let key = PlaybackStoreRegistry.shared.register(store)

        var headers = config.httpAdditionalHeaders ?? [:]
        headers[ReplayProtocolContext.headerName] = key
        config.httpAdditionalHeaders = headers

        return URLSession(configuration: config)
    }

    /// Clear playback state.
    public static func clear() async {
        await PlaybackStore.shared.clear()
    }
}

// MARK: - Playback Configuration

/// A scope for replay playback configuration.
///
/// Use `.global` when you rely on globally registered `URLProtocol` state.
/// Use `.test` to isolate playback state per test or task.
public enum ReplayScope: Sendable {
    /// Uses global `URLProtocol.registerClass(...)` and `PlaybackStore.shared`.
    case global

    /// Uses an isolated `PlaybackStore` for the current test/task only.
    ///
    /// Note: This requires using a `URLSession` configured with `PlaybackURLProtocol`
    /// (for example, `Replay.session`).
    case test
}

/// Configuration for replaying HTTP traffic from HAR logs or in-memory stubs.
///
/// Use this type with `Playback.session(configuration:baseConfiguration:)`
/// or with `PlaybackStore.configure(_:)` to control:
/// - The replay source (HAR file, entries, or stubs)
/// - The playback behavior (strict, passthrough, live)
/// - The recording policy (none, once, rewrite)
/// - The matching and filtering strategy
public struct PlaybackConfiguration: Sendable {
    /// The source of recorded traffic to replay.
    public let source: Source

    /// How recorded entries are used (and whether the network is allowed).
    public let playbackMode: Replay.PlaybackMode

    /// Whether fixtures should be recorded, and if so, how.
    public let recordMode: Replay.RecordMode

    /// Matchers used to match incoming requests to recorded entries.
    public let matchers: [Matcher]

    /// Filters applied to entries as they are recorded.
    public let filters: [Filter]

    /// A source of recorded traffic for playback.
    public enum Source: Sendable {
        /// Loads entries from a HAR file.
        case file(URL)

        /// Uses the provided entries directly.
        ///
        /// This is useful for tests or tools that construct `HAR.Entry` values programmatically.
        case entries([HAR.Entry])

        /// Uses stubs converted to HAR entries.
        case stubs([Stub])
    }

    /// Creates a playback configuration.
    ///
    /// - Parameters:
    ///   - source: The replay source.
    ///   - playbackMode: How recorded entries are used and whether the network is allowed.
    ///   - recordMode: Whether and how to record fixtures.
    ///   - matchers: Matchers used to match incoming requests to entries.
    ///   - filters: Filters applied to newly recorded entries.
    public init(
        source: Source,
        playbackMode: Replay.PlaybackMode = .strict,
        recordMode: Replay.RecordMode = .none,
        matchers: [Matcher] = .default,
        filters: [Filter] = []
    ) {
        self.source = source
        self.playbackMode = playbackMode
        self.recordMode = recordMode
        self.matchers = matchers
        self.filters = filters
    }
}

enum ReplayContext {
    @TaskLocal
    static var playbackStore: PlaybackStore?
}

enum ReplayProtocolContext {
    static let headerName = "X-Replay-Playback-Context"
}

/// A tiny registry used to route requests to an isolated `PlaybackStore` when using `.test` scope.
///
/// The store identity is carried via a private HTTP header on sessions created by `Replay.session`.
final class PlaybackStoreRegistry: @unchecked Sendable {
    static let shared = PlaybackStoreRegistry()

    private let lock = NSLock()
    private var stores: [String: PlaybackStore] = [:]

    static func key(for store: PlaybackStore) -> String {
        // Stable for the lifetime of the object.
        String(UInt(bitPattern: ObjectIdentifier(store)))
    }

    func register(_ store: PlaybackStore) -> String {
        let key = Self.key(for: store)
        lock.lock()
        stores[key] = store
        lock.unlock()
        return key
    }

    func unregister(key: String) {
        lock.lock()
        stores[key] = nil
        lock.unlock()
    }

    func store(for key: String) -> PlaybackStore? {
        lock.lock()
        let store = stores[key]
        lock.unlock()
        return store
    }
}

// MARK: - Playback URLProtocol

/// Wrapper to send non-Sendable values across isolation boundaries when safety is guaranteed.
struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
}

/// A `URLProtocol` implementation that replays HTTP responses from recorded traffic.
///
/// This protocol routes requests to a `PlaybackStore`,
/// returning a recorded response when a match is found.
/// For network requests (live/passthrough mode), responses are streamed incrementally,
/// enabling support for Server-Sent Events and other streaming protocols.
public final class PlaybackURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "ReplayPlaybackHandled"
    private var streamTask: Task<Void, Never>?
    private var urlSessionTask: URLSessionTask?

    public override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }
        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)
        let markedRequest = mutableRequest as URLRequest

        // URLProtocol predates Swift concurrency; wrap self to cross isolation boundary
        let sendableSelf = UnsafeSendable(value: self)
        streamTask = Task {
            let `self` = sendableSelf.value
            do {
                var matchingRequest = markedRequest

                let store: PlaybackStore
                if let key = matchingRequest.value(forHTTPHeaderField: ReplayProtocolContext.headerName),
                    let registered = PlaybackStoreRegistry.shared.store(for: key)
                {
                    // Strip the internal routing header so it never affects matching or recordings.
                    if var headers = matchingRequest.allHTTPHeaderFields {
                        headers[ReplayProtocolContext.headerName] = nil
                        matchingRequest.allHTTPHeaderFields = headers
                    }
                    store = registered
                } else {
                    store = PlaybackStore.shared
                }

                let disposition = try await store.checkRequest(matchingRequest)

                switch disposition {
                case .recorded(let response, let data):
                    self.client?.urlProtocol(
                        self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    self.client?.urlProtocol(self, didLoad: data)
                    self.client?.urlProtocolDidFinishLoading(self)

                case .error(let error):
                    throw error

                case .network(let shouldRecord):
                    // Network request: stream bytes incrementally
                    let startTime = Date()

                    // Use a delegate-based approach for proper cancellation support
                    let delegate = StreamingDelegate()
                    let config = URLSessionConfiguration.ephemeral
                    config.timeoutIntervalForRequest = .infinity
                    config.timeoutIntervalForResource = .infinity
                    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
                    let dataTask = session.dataTask(with: matchingRequest)

                    // Initialize dataStream BEFORE starting the request
                    let dataStream = delegate.dataStream

                    // Store task reference for cancellation
                    self.urlSessionTask = dataTask
                    dataTask.resume()

                    // Wait for response
                    let httpResponse = try await delegate.waitForResponse()

                    self.client?.urlProtocol(
                        self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)

                    // Stream data incrementally, collecting for potential recording
                    // Use a class to allow capturing in the finish handler
                    final class StreamState: @unchecked Sendable {
                        var collectedData = Data()
                        var finished = false
                    }
                    let state = StreamState()
                    let protocolId = ObjectIdentifier(self)
                    let capturedRequest = matchingRequest
                    let capturedResponse = httpResponse

                    // Register finish handler for flush()
                    if shouldRecord {
                        await store.registerStreamingProtocol(id: protocolId) { [state] in
                            guard !state.finished, !state.collectedData.isEmpty else { return }
                            state.finished = true
                            let duration = Date().timeIntervalSince(startTime)
                            do {
                                try await store.recordResponse(
                                    request: capturedRequest,
                                    response: capturedResponse,
                                    data: state.collectedData,
                                    duration: duration,
                                    startTime: startTime
                                )
                            } catch {
                                print("Replay: Failed to record streaming response: \(error)")
                            }
                        }
                    }

                    let urlTask = dataTask
                    do {
                        try await withTaskCancellationHandler {
                            for try await chunk in dataStream {
                                if Task.isCancelled { break }
                                state.collectedData.append(chunk)
                                self.client?.urlProtocol(self, didLoad: chunk)
                            }
                        } onCancel: {
                            urlTask.cancel()
                        }
                    } catch {
                        // Ignore errors (including cancellation) and proceed to recording
                    }

                    // Record if loop exited naturally (not via flush)
                    if shouldRecord, !state.finished, !state.collectedData.isEmpty {
                        state.finished = true
                        await store.unregisterStreamingProtocol(id: protocolId)
                        let duration = Date().timeIntervalSince(startTime)
                        do {
                            try await store.recordResponse(
                                request: matchingRequest,
                                response: httpResponse,
                                data: state.collectedData,
                                duration: duration,
                                startTime: startTime
                            )
                        } catch {
                            print("Replay: Failed to record streaming response: \(error)")
                        }
                    }

                    session.invalidateAndCancel()
                    self.client?.urlProtocolDidFinishLoading(self)
                }
            } catch {
                if !Task.isCancelled {
                    self.client?.urlProtocol(self, didFailWithError: error)
                }
            }
        }
    }

    public override func stopLoading() {
        urlSessionTask?.cancel()
        urlSessionTask = nil
        streamTask?.cancel()
        streamTask = nil
    }
}

// MARK: - Streaming Delegate

/// A delegate that bridges URLSession callbacks to async streams for SSE support.
private final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var responseContinuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var dataContinuation: AsyncThrowingStream<Data, Error>.Continuation?

    var dataStream: AsyncThrowingStream<Data, Error> {
        if let stream = _dataStream { return stream }
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            self.dataContinuation = continuation
        }
        _dataStream = stream
        return stream
    }
    private var _dataStream: AsyncThrowingStream<Data, Error>?

    func waitForResponse() async throws -> HTTPURLResponse {
        try await withCheckedThrowingContinuation { continuation in
            self.responseContinuation = continuation
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            responseContinuation?.resume(returning: httpResponse)
            responseContinuation = nil
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dataContinuation?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            responseContinuation?.resume(throwing: error)
            responseContinuation = nil
            dataContinuation?.finish(throwing: error)
        } else {
            dataContinuation?.finish()
        }
    }
}

// MARK: - Playback Store

/// An actor that replays requests from recorded traffic.
///
/// Configure the store with `configure(_:)`,
/// then call `handleRequest(_:)` to obtain a replayed response.
public actor PlaybackStore {
    /// The shared playback store.
    public static let shared = PlaybackStore()

    /// Active streaming protocols that need to finish recording.
    private var activeStreamingProtocols: [ObjectIdentifier: (@Sendable () async -> Void)] = [:]

    /// Waits for all active streaming recordings to complete.
    /// Call this before tearing down to ensure recordings are saved.
    public func flush() async {
        let handlers = activeStreamingProtocols.values
        activeStreamingProtocols.removeAll()
        for finish in handlers {
            await finish()
        }
    }

    /// Registers an active streaming protocol's finish handler.
    func registerStreamingProtocol(id: ObjectIdentifier, finish: @escaping @Sendable () async -> Void) {
        activeStreamingProtocols[id] = finish
    }

    /// Unregisters a streaming protocol.
    func unregisterStreamingProtocol(id: ObjectIdentifier) {
        activeStreamingProtocols[id] = nil
    }

    private var configuration: PlaybackConfiguration?
    private var entries: [HAR.Entry] = []
    private var recordingEnabled: Bool = false
    private var effectivePlaybackMode: Replay.PlaybackMode = .strict

    /// Configures the store for playback.
    ///
    /// - Parameter config: The playback configuration to apply.
    /// - Throws: Any error thrown while loading the configured source.
    public func configure(_ config: PlaybackConfiguration) async throws {
        configuration = config
        recordingEnabled = false
        effectivePlaybackMode = config.playbackMode

        switch config.source {
        case .file(let url):
            if config.recordMode == .rewrite, FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            do {
                let log = try HAR.load(from: url)
                entries = log.entries
                // Match pytest-recording semantics: when a fixture exists, `once` does not permit
                // extending it and does not allow network fallback.
                if config.recordMode == .once {
                    effectivePlaybackMode = .strict
                    recordingEnabled = false
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                entries = []
                recordingEnabled = config.recordMode != .none

                if !recordingEnabled, config.playbackMode == .strict {
                    throw ReplayError.archiveNotFound(url)
                }
            } catch {
                throw error
            }

        case .entries(let provided):
            entries = provided
            recordingEnabled = false

        case .stubs(let stubs):
            entries = try stubs.map { stub in
                try makeEntry(from: stub)
            }
            recordingEnabled = false
        }
    }

    /// Expose entries for debugging/attachments.
    public func getAvailableEntries() -> [HAR.Entry] {
        entries
    }

    /// The result of checking whether a request matches a recorded entry.
    public enum RequestDisposition: Sendable {
        /// Use the recorded entry's response.
        case recorded(HTTPURLResponse, Data)
        /// No match found; go to the network (with optional recording).
        case network(shouldRecord: Bool)
        /// No match and strict mode - throw an error.
        case error(ReplayError)
    }

    /// Checks how a request should be handled based on playback configuration.
    ///
    /// This method determines whether a request matches a recorded entry or should
    /// go to the network. It does not perform any network requests itself.
    ///
    /// - Parameter request: The request to check.
    /// - Returns: A disposition indicating how to handle the request.
    public func checkRequest(_ request: URLRequest) throws -> RequestDisposition {
        guard let config = configuration else {
            throw ReplayError.notConfigured
        }

        // `.live` ignores any recorded entries and always hits the network.
        if effectivePlaybackMode != .live,
            let entry = config.matchers.firstMatch(for: request, in: entries)
        {
            let (response, data) = try entry.toURLResponse()
            return .recorded(response, data)
        }

        if effectivePlaybackMode == .strict, !recordingEnabled {
            // Use different error for stubs vs HAR archives
            if case .stubs(let stubs) = config.source {
                let availableStubs = stubs.map { stub in
                    let location = stub.sourceLocation.map { " (\($0.description))" } ?? ""
                    return "  • \(stub.method.rawValue) \(stub.url.absoluteString)\(location)"
                }.joined(separator: "\n")

                return .error(
                    ReplayError.noMatchingStub(
                        method: request.httpMethod ?? "GET",
                        url: request.url?.absoluteString ?? "unknown",
                        availableStubs: availableStubs.isEmpty ? "  (none)" : availableStubs
                    ))
            } else {
                return .error(
                    ReplayError.noMatchingEntry(
                        method: request.httpMethod ?? "GET",
                        url: request.url?.absoluteString ?? "unknown",
                        archivePath: archivePathDescription(for: config.source)
                    ))
            }
        }

        return .network(shouldRecord: recordingEnabled)
    }

    /// Records a completed network response.
    ///
    /// Call this after streaming a network response to record it to the HAR file.
    ///
    /// - Parameters:
    ///   - request: The original request.
    ///   - response: The HTTP response received.
    ///   - data: The complete response body.
    ///   - startTime: When the request started.
    ///   - duration: How long the request took.
    public func recordResponse(
        request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        duration: TimeInterval,
        startTime: Date
    ) async throws {
        guard let config = configuration else {
            return
        }

        var entry = try HAR.Entry(
            request: request,
            response: response,
            data: data,
            startTime: startTime,
            duration: duration
        )

        for filter in config.filters {
            entry = await filter.apply(to: entry)
        }

        entries.append(entry)

        if case .file(let url) = config.source {
            var log = (try? HAR.load(from: url)) ?? HAR.create()
            log.entries = entries
            try HAR.save(log, to: url)
        }
    }

    /// Handles a URL request using the current playback configuration.
    ///
    /// In `.strict` playback mode, this method throws when no matching entry is found.
    /// In `.passthrough` playback mode, this method falls back to the live network on no match.
    /// In `.live` playback mode, this method always performs the request against the live network.
    ///
    /// Recording is controlled independently via `recordMode`.
    ///
    /// - Parameter request: The request to handle.
    /// - Returns: A tuple of `HTTPURLResponse` and body `Data`.
    ///
    /// - Note: This method buffers the entire response, making it unsuitable for streaming
    ///   responses like Server-Sent Events. For streaming support, use `checkRequest(_:)`
    ///   and handle network requests with `URLSession.bytes(for:)`.
    public func handleRequest(_ request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        switch try checkRequest(request) {
        case .recorded(let response, let data):
            return (response, data)
        case .error(let error):
            throw error
        case .network(let shouldRecord):
            let startTime = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReplayError.invalidResponse
            }

            if shouldRecord {
                let duration = Date().timeIntervalSince(startTime)
                try await recordResponse(
                    request: request,
                    response: httpResponse,
                    data: data,
                    duration: duration,
                    startTime: startTime
                )
            }

            return (httpResponse, data)
        }
    }

    /// Clears the active configuration and any loaded entries.
    public func clear() {
        configuration = nil
        entries = []
    }

    private func archivePathDescription(for source: PlaybackConfiguration.Source) -> String {
        switch source {
        case .file(let url):
            return url.path
        case .entries:
            return "<entries-array>"
        case .stubs:
            return "<stubs>"
        }
    }

    private func makeEntry(from stub: Stub) throws -> HAR.Entry {
        var request = URLRequest(url: stub.url)
        request.httpMethod = stub.method.rawValue

        guard
            let response = HTTPURLResponse(
                url: stub.url,
                statusCode: stub.status,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )
        else {
            throw ReplayError.invalidResponse
        }

        return try HAR.Entry(
            request: request,
            response: response,
            data: stub.body ?? Data(),
            startTime: Date(),
            duration: 0
        )
    }
}
