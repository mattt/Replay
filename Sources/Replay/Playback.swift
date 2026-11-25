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
    /// Built-in query filters also normalize URLs for `.url` and `.query` playback matching.
    public let filters: [Filter]

    /// The largest request body, in bytes, that playback reads from a request's body stream.
    ///
    /// URLSession can give a request's body to the URL protocol as a stream.
    /// Playback reads that stream into memory only when it needs the body:
    /// when a matcher inspects the body (`.body` or `.custom`) and the playback mode is not `.live`,
    /// or when recording is enabled.
    /// Otherwise the request goes to the network with its stream.
    ///
    /// If playback needs a body that is larger than this limit,
    /// the request fails with `URLError(.dataLengthExceedsMaximum)`.
    /// The default is `Replay.defaultMaximumRequestBodySize` (10 MiB).
    public let maximumRequestBodySize: Int

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
    ///     Built-in query filters also apply during URL and query matching.
    ///   - maximumRequestBodySize: The largest request body, in bytes,
    ///     that playback reads from a request's body stream.
    ///     The value must be zero or more.
    ///     Pass `Int.max` to read bodies of any size.
    public init(
        source: Source,
        playbackMode: Replay.PlaybackMode = .strict,
        recordMode: Replay.RecordMode = .none,
        matchers: [Matcher] = .default,
        filters: [Filter] = [],
        maximumRequestBodySize: Int = Replay.defaultMaximumRequestBodySize
    ) {
        precondition(maximumRequestBodySize >= 0, "maximumRequestBodySize must be zero or more")
        self.source = source
        self.playbackMode = playbackMode
        self.recordMode = recordMode
        self.matchers = matchers
        self.filters = filters
        self.maximumRequestBodySize = maximumRequestBodySize
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

extension URLRequest {
    /// Returns a copy whose body is in `httpBody`, read from `httpBodyStream` if needed.
    ///
    /// On Darwin, URLSession hands a URLProtocol the request with `httpBody` set to nil
    /// and the body in `httpBodyStream`. Matching (`.body` and `.custom`) and recording (`postData`)
    /// read `httpBody`, so the protocols read the stream back when they need the body.
    ///
    /// The body must be read in full from a stream that has not been opened.
    /// If the stream was already opened or closed, or a read fails,
    /// this method throws `URLError(.requestBodyStreamExhausted)`
    /// rather than return a request with a partial or empty body.
    /// For a read failure, the error's underlying error is the stream's error, if any.
    ///
    /// - Parameters:
    ///   - limit: The maximum number of body bytes to read. It must be zero or more.
    ///     If the stream has more bytes, this method throws `URLError(.dataLengthExceedsMaximum)`.
    ///   - isCancelled: Called before each read.
    ///     If it returns `true`, this method closes the stream and throws `CancellationError`.
    func withBodyReadFromStream(
        limit: Int,
        isCancelled: () -> Bool = { false }
    ) throws -> URLRequest {
        precondition(limit >= 0, "limit must be zero or more")
        guard httpBody == nil, let stream = httpBodyStream else { return self }
        guard stream.streamStatus == .notOpen else {
            throw URLError(.requestBodyStreamExhausted)
        }

        stream.open()
        defer { stream.close() }

        var body = Data()
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while true {
            if isCancelled() { throw CancellationError() }
            // Read at most one byte past the limit, so an oversized body is detected
            // without reading the rest of it.
            // `body.count` never exceeds `limit` here, so `remaining` is not negative,
            // and `+ 1` runs only when it cannot overflow.
            let remaining = limit - body.count
            let maxLength = remaining < bufferSize ? remaining + 1 : bufferSize
            let count = stream.read(&buffer, maxLength: maxLength)
            if count == 0 { break }
            if count < 0 {
                var userInfo: [String: Any] = [:]
                if let streamError = stream.streamError {
                    userInfo[NSUnderlyingErrorKey] = streamError
                }
                throw URLError(.requestBodyStreamExhausted, userInfo: userInfo)
            }
            body.append(buffer, count: count)
            if body.count > limit {
                throw URLError(
                    .dataLengthExceedsMaximum,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The request body is larger than Replay's limit of \(limit) bytes. "
                            + "Increase maximumRequestBodySize to match or record this request."
                    ]
                )
            }
        }

        var copy = self
        copy.httpBody = body  // Also clears `httpBodyStream`.
        return copy
    }
}

private func requestDescription(_ request: URLRequest) -> String {
    let method = request.httpMethod ?? "GET"
    let url = request.url?.absoluteString ?? "<unknown URL>"
    return "\(method) \(url)"
}

/// A `URLProtocol` implementation that replays HTTP responses from recorded traffic.
///
/// This protocol routes requests to a `PlaybackStore`,
/// returning a recorded response when a match is found.
/// For network requests (live/passthrough mode), responses are streamed incrementally,
/// enabling support for Server-Sent Events and other streaming protocols.
public final class PlaybackURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "ReplayPlaybackHandled"
    // `startLoading()` and `stopLoading()` run on the client's thread,
    // while the stream task stores the URLSession task from another thread.
    private let lock = NSLock()
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
        let task = Task {
            let urlProtocol = sendableSelf.value
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

                // Read the body back from its stream only if matching or recording uses it.
                // Otherwise the request keeps its stream, and the network transport reads it.
                if let limit = await store.requestBodyLimit() {
                    matchingRequest = try matchingRequest.withBodyReadFromStream(limit: limit) {
                        Task.isCancelled
                    }
                }

                let disposition = try await store.checkRequest(matchingRequest)

                switch disposition {
                case .recorded(let response, let data):
                    urlProtocol.client?.urlProtocol(
                        urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
                    urlProtocol.client?.urlProtocol(urlProtocol, didLoad: data)
                    urlProtocol.client?.urlProtocolDidFinishLoading(urlProtocol)

                case .error(let error):
                    throw error

                case .network(let shouldRecord):
                    // Network request: stream bytes incrementally
                    let startTime = Date()

                    // Use a delegate-based approach for proper cancellation support
                    let delegate = StreamingDelegate()
                    // The streaming URLSession delegate only knows about URLSession callbacks.
                    // Keep a back-reference to the PlaybackURLProtocol
                    // so authentication challenges can be forwarded to the URLProtocol client that started this load.
                    delegate.urlProtocol = urlProtocol
                    let config = URLSessionConfiguration.ephemeral
                    #if canImport(FoundationNetworking)
                        // FoundationNetworking converts request timeouts to integer milliseconds.
                        // A large finite value avoids trapping when a stream starts on Linux.
                        let streamingTimeout = TimeInterval(Int32.max / 1000)
                        config.timeoutIntervalForRequest = streamingTimeout
                        config.timeoutIntervalForResource = streamingTimeout
                    #else
                        config.timeoutIntervalForRequest = .infinity
                        config.timeoutIntervalForResource = .infinity
                    #endif
                    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
                    defer { session.invalidateAndCancel() }
                    let dataTask = session.dataTask(with: matchingRequest)
                    let sendableDataTask = UnsafeSendable(value: dataTask)

                    // Initialize dataStream BEFORE starting the request
                    let dataStream = delegate.dataStream

                    // Store task reference for cancellation
                    urlProtocol.setURLSessionTask(dataTask)
                    dataTask.resume()

                    // Wait for response.
                    // Cancel the transport if loading stops before the response arrives.
                    let urlTask = dataTask
                    let httpResponse = try await withTaskCancellationHandler {
                        try await delegate.waitForResponse()
                    } onCancel: {
                        urlTask.cancel()
                    }

                    urlProtocol.client?.urlProtocol(
                        urlProtocol, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)

                    // Stream data incrementally, collecting for potential recording
                    // Use a class to allow capturing in the finish handler
                    final class StreamState: @unchecked Sendable {
                        private let lock = NSLock()
                        private var collectedData = Data()
                        private var finished = false

                        func append(_ chunk: Data) -> Bool {
                            lock.lock()
                            defer { lock.unlock() }
                            guard !finished else { return false }
                            collectedData.append(chunk)
                            return true
                        }

                        func finish(requireBody: Bool = false) -> Data? {
                            lock.lock()
                            defer { lock.unlock() }
                            guard !finished, !requireBody || !collectedData.isEmpty else { return nil }
                            finished = true
                            return collectedData
                        }

                        func fail() -> Bool {
                            lock.lock()
                            defer { lock.unlock() }
                            guard !finished else { return false }
                            finished = true
                            return true
                        }
                    }
                    let state = StreamState()
                    let protocolId = ObjectIdentifier(urlProtocol)
                    let capturedRequest = matchingRequest
                    let capturedResponse = httpResponse

                    // Explicit flushing can finish any active streaming recording.
                    if shouldRecord {
                        await store.registerStreamingProtocol(id: protocolId) { [state, sendableDataTask] in
                            guard let data = state.finish(requireBody: true) else { return }
                            let duration = Date().timeIntervalSince(startTime)
                            do {
                                try await store.recordResponse(
                                    request: capturedRequest,
                                    response: capturedResponse,
                                    data: data,
                                    duration: duration,
                                    startTime: startTime
                                )
                            } catch {
                                print(
                                    "Replay: Failed to record response for \(requestDescription(capturedRequest)): \(error)"
                                )
                            }

                            // Stop the underlying stream so it doesn't keep accumulating data after `flush()` is called
                            sendableDataTask.value.cancel()
                        }
                    }

                    do {
                        try await withTaskCancellationHandler {
                            for try await chunk in dataStream {
                                try Task.checkCancellation()
                                guard state.append(chunk) else { break }
                                urlProtocol.client?.urlProtocol(urlProtocol, didLoad: chunk)
                            }
                        } onCancel: {
                            urlTask.cancel()
                        }
                        try Task.checkCancellation()
                    } catch {
                        let failed = state.fail()
                        await store.unregisterStreamingProtocol(id: protocolId)
                        // A flush already saved the stream and deliberately cancelled its transport.
                        // Otherwise, preserve the transport failure and do not save a partial fixture.
                        if failed { throw error }
                    }

                    // Record if loop exited naturally (not via flush)
                    await store.unregisterStreamingProtocol(id: protocolId)
                    if shouldRecord, let data = state.finish() {
                        let duration = Date().timeIntervalSince(startTime)
                        do {
                            try await store.recordResponse(
                                request: matchingRequest,
                                response: httpResponse,
                                data: data,
                                duration: duration,
                                startTime: startTime
                            )
                        } catch {
                            print(
                                "Replay: Failed to record response for \(requestDescription(matchingRequest)): \(error)"
                            )
                        }
                    }

                    urlProtocol.client?.urlProtocolDidFinishLoading(urlProtocol)
                }
            } catch {
                if !Task.isCancelled {
                    urlProtocol.client?.urlProtocol(urlProtocol, didFailWithError: error)
                }
            }
        }
        lock.lock()
        streamTask = task
        lock.unlock()
    }

    private func setURLSessionTask(_ task: URLSessionTask) {
        lock.lock()
        urlSessionTask = task
        lock.unlock()
    }

    public override func stopLoading() {
        lock.lock()
        let urlSessionTask = self.urlSessionTask
        let streamTask = self.streamTask
        self.urlSessionTask = nil
        self.streamTask = nil
        lock.unlock()

        urlSessionTask?.cancel()
        streamTask?.cancel()
    }
}

// MARK: - Streaming Delegate

/// A delegate that bridges URLSession callbacks to async streams for SSE support.
final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// The response hand-off between URLSession's delegate queue and `waitForResponse()`.
    /// URLSession can deliver the response, or fail, before the caller starts to wait.
    private enum ResponseState {
        case pending
        case waiting(CheckedContinuation<HTTPURLResponse, Error>)
        case ready(Result<HTTPURLResponse, Error>)
        case delivered
    }

    private let lock = NSLock()
    private var responseState = ResponseState.pending

    // AsyncThrowingStream buffers chunks that arrive before iteration starts,
    // and its continuation is safe to use from the delegate queue.
    let dataStream: AsyncThrowingStream<Data, Error>
    private let dataContinuation: AsyncThrowingStream<Data, Error>.Continuation

    // Held weakly because URLProtocol owns the streaming task that owns this delegate.
    weak var urlProtocol: PlaybackURLProtocol?

    override init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        dataStream = AsyncThrowingStream { continuation = $0 }
        dataContinuation = continuation
        super.init()
    }

    /// Returns the HTTP response for the task, whether it arrived before or after this call.
    ///
    /// Call this method at most once.
    func waitForResponse() async throws -> HTTPURLResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            switch responseState {
            case .pending:
                responseState = .waiting(continuation)
                lock.unlock()
            case .ready(let result):
                responseState = .delivered
                lock.unlock()
                continuation.resume(with: result)
            case .waiting, .delivered:
                lock.unlock()
                preconditionFailure("waitForResponse() must be called only once")
            }
        }
    }

    /// Settles the response with the first result; later results are ignored.
    private func settleResponse(_ result: Result<HTTPURLResponse, Error>) {
        lock.lock()
        switch responseState {
        case .pending:
            responseState = .ready(result)
            lock.unlock()
        case .waiting(let continuation):
            responseState = .delivered
            lock.unlock()
            continuation.resume(with: result)
        case .ready, .delivered:
            lock.unlock()
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            settleResponse(.success(httpResponse))
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dataContinuation.yield(data)
    }

    // Connection-level challenges (TLS server trust, client certificates) arrive through
    // this session-level callback rather than the task-level one below. Both must be
    // forwarded, otherwise trust decisions silently fall back to default handling.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        forward(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        forward(challenge, completionHandler: completionHandler)
    }

    private func forward(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let urlProtocol, let client = urlProtocol.client else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // URLProtocol clients answer challenges through URLAuthenticationChallengeSender,
        // while URLSession expects a completion handler.
        // Rebuild the challenge with a sender that bridges the client's eventual decision back to URLSession.
        let forwardedChallenge = URLAuthenticationChallenge(
            protectionSpace: challenge.protectionSpace,
            proposedCredential: challenge.proposedCredential,
            previousFailureCount: challenge.previousFailureCount,
            failureResponse: challenge.failureResponse,
            error: challenge.error,
            sender: PlaybackChallengeForwarder(completionHandler: completionHandler)
        )
        client.urlProtocol(urlProtocol, didReceive: forwardedChallenge)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            settleResponse(.failure(error))
            dataContinuation.finish(throwing: error)
        } else {
            // A task that completes without an HTTP response must not leave the caller waiting.
            settleResponse(.failure(URLError(.badServerResponse)))
            dataContinuation.finish()
        }
    }
}

/// Bridges URLProtocolClient challenge decisions back into URLSession's challenge completion handler.
private final class PlaybackChallengeForwarder: NSObject, URLAuthenticationChallengeSender, @unchecked Sendable {
    private let lock = NSLock()
    private var completionHandler: ((URLSession.AuthChallengeDisposition, URLCredential?) -> Void)?

    init(completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        self.completionHandler = completionHandler
    }

    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        complete(.useCredential, credential)
    }

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        // "Continue without a credential" maps to URLSession's default handling,
        // not to `.useCredential` with a nil credential.
        complete(.performDefaultHandling, nil)
    }

    func cancel(_ challenge: URLAuthenticationChallenge) {
        complete(.cancelAuthenticationChallenge, nil)
    }

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        complete(.performDefaultHandling, nil)
    }

    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        complete(.rejectProtectionSpace, nil)
    }

    private func complete(_ disposition: URLSession.AuthChallengeDisposition, _ credential: URLCredential?) {
        // A challenge sender may receive more than one callback from a defensive client;
        // URLSession completion handlers must only be invoked once.
        lock.lock()
        let handler = completionHandler
        completionHandler = nil
        lock.unlock()

        handler?(disposition, credential)
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

    internal private(set) var configuration: PlaybackConfiguration?
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
            if config.recordMode == .rewrite {
                entries = []
                recordingEnabled = true
                return
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

    /// Returns the size limit for reading a request body from its stream,
    /// or `nil` if neither matching nor recording uses the body.
    ///
    /// Matching uses the body when a matcher inspects it (`.body` or `.custom`)
    /// and the playback mode is not `.live`. Recording always uses the body.
    func requestBodyLimit() -> Int? {
        guard let config = configuration else { return nil }
        let matchingUsesBody =
            effectivePlaybackMode != .live && config.matchers.contains { $0.inspectsBody }
        guard recordingEnabled || matchingUsesBody else { return nil }
        return config.maximumRequestBodySize
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
            let entry = config.matchers.firstMatch(for: request, in: entries, filters: config.filters)
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

        try append(entry, using: config)
    }

    /// Records a pre-built HAR entry.
    ///
    /// This method appends the entry to the store and persists it
    /// when the source is a file. Filters are **not** applied;
    /// callers are responsible for filtering before calling this method.
    ///
    /// - Parameter entry: The entry to record.
    public func recordEntry(_ entry: HAR.Entry) throws {
        try append(entry, using: configuration)
    }

    private func append(_ entry: HAR.Entry, using config: PlaybackConfiguration?) throws {
        guard let config, case .file(let url) = config.source else {
            entries.append(entry)
            return
        }

        let startsRewrite = config.recordMode == .rewrite && entries.isEmpty
        var log = startsRewrite ? HAR.create() : ((try? HAR.load(from: url)) ?? HAR.create())
        log.entries = entries + [entry]
        try HAR.save(log, to: url, options: startsRewrite ? .atomic : [])
        entries = log.entries
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
        if !stub.requestHeaders.isEmpty {
            request.allHTTPHeaderFields = stub.requestHeaders
        }

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
