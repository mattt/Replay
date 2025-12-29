import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Capture Session Factory

/// The Capture API records live HTTP traffic into HAR entries.
///
/// This is intentionally independent of `@Test(.replay)` so it can be used for:
/// - Recording traffic from tooling or sample apps (outside of tests)
/// - Custom recording workflows (for example, streaming entries to a handler)
/// - Exporting traffic to HAR for use in external tools
///
/// For test recording/playback, prefer `ReplayTrait` (`@Test(.replay)`) and
/// enable recording explicitly with `REPLAY_RECORD_MODE=once` (or `rewrite`).
///
/// Use `Capture.session(configuration:baseConfiguration:)` to create a `URLSession`
/// that records requests through `CaptureURLProtocol`.
///
public enum Capture {
    /// Creates a `URLSession` configured for capturing HTTP traffic.
    ///
    /// - Parameters:
    ///   - configuration: The capture configuration specifying destination,
    ///     filters, and optional matchers.
    ///   - baseConfiguration: The base `URLSessionConfiguration` to extend.
    /// - Returns: A configured `URLSession` that records traffic as HAR entries.
    public static func session(
        configuration: CaptureConfiguration,
        baseConfiguration: URLSessionConfiguration = .default
    ) async -> URLSession {
        let config = baseConfiguration
        var protocols = config.protocolClasses ?? []
        protocols.insert(CaptureURLProtocol.self, at: 0)
        config.protocolClasses = protocols

        await CaptureStore.shared.configure(configuration)

        return URLSession(configuration: config)
    }

    /// Captured entries (when using `.memory` destination).
    public static var entries: [HAR.Entry] {
        get async {
            await CaptureStore.shared.getEntries()
        }
    }

    /// Clears the active capture configuration and any captured entries.
    public static func clear() async {
        await CaptureStore.shared.clear()
    }
}

// MARK: - Capture Configuration

/// Configuration for capturing HTTP traffic into HAR entries.
///
/// Use this type with `Capture.session(configuration:baseConfiguration:)`
/// to define where captured entries are written,
/// and how entries are filtered or matched.
public struct CaptureConfiguration: Sendable {
    /// The destination for captured entries.
    public let destination: Destination

    /// Filters applied to each captured entry,
    /// in the order provided.
    public let filters: [Filter]

    /// Matchers used to decide whether a request is captured.
    ///
    /// When `nil`,
    /// all requests are eligible for capture.
    public let matchers: [Matcher]?  // Optional: only capture matching requests

    /// A destination for captured HAR entries.
    public enum Destination: Sendable {
        /// Writes a HAR log to the specified file URL.
        case file(URL)

        /// Calls the handler for each captured entry.
        ///
        /// Use this destination to stream entries to custom storage,
        /// or to integrate with your own logging pipeline.
        case handler(@Sendable (HAR.Entry) async -> Void)

        /// Stores captured entries in memory.
        ///
        /// Access entries via `Capture.entries`.
        case memory  // Store in memory for inspection
    }

    /// Creates a capture configuration.
    ///
    /// - Parameters:
    ///   - destination: Where captured entries are written.
    ///   - filters: Filters applied to each entry before it is stored.
    ///   - matchers: Matchers used to decide which requests are captured.
    public init(
        destination: Destination,
        filters: [Filter] = [],
        matchers: [Matcher]? = nil
    ) {
        self.destination = destination
        self.filters = filters
        self.matchers = matchers
    }
}

// MARK: - Capture URLProtocol

/// A `URLProtocol` implementation that records HTTP traffic as HAR entries.
///
/// `CaptureURLProtocol` forwards responses to the requesting client,
/// and records the request/response pair asynchronously.
public final class CaptureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "ReplayCaptureHandled"

    private var startTime: Date?
    private var dataTask: URLSessionDataTask?

    public override class func canInit(with request: URLRequest) -> Bool {
        // Prevent infinite loops
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }

        // Note: capture matching/filtering is applied later during recording
        // (in `CaptureStore.recordEntry(...)`).
        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        startTime = Date()

        // Mark request as handled
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        let session = URLSession.shared
        dataTask = session.dataTask(with: mutableRequest as URLRequest) {
            [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            guard
                let httpResponse = response as? HTTPURLResponse,
                let data,
                let startTime = self.startTime
            else {
                self.client?.urlProtocol(self, didFailWithError: ReplayError.invalidResponse)
                return
            }

            let duration = Date().timeIntervalSince(startTime)

            // Forward to client first
            self.client?.urlProtocol(
                self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)

            // Record the entry asynchronously
            let capturedRequest = self.request
            Task { @Sendable in
                await CaptureStore.shared.recordEntry(
                    request: capturedRequest,
                    response: httpResponse,
                    data: data,
                    startTime: startTime,
                    duration: duration
                )
            }
        }

        dataTask?.resume()
    }

    public override func stopLoading() {
        dataTask?.cancel()
    }

}

// MARK: - Capture Store (Actor for thread safety)

/// An actor that stores capture configuration and captured entries.
///
/// This actor is used internally by `Capture`,
/// and can also be used directly when integrating capture
/// with custom destinations.
public actor CaptureStore {
    /// The shared capture store.
    public static let shared = CaptureStore()

    private var configuration: CaptureConfiguration?
    private var entries: [HAR.Entry] = []
    private var log: HAR.Log?

    var currentConfiguration: CaptureConfiguration? { configuration }

    /// Sets the active capture configuration.
    ///
    /// Calling this method clears any previously captured entries.
    ///
    /// - Parameter config: The configuration to apply.
    public func configure(_ config: CaptureConfiguration) {
        configuration = config
        entries = []

        if case .file = config.destination {
            log = HAR.create()
        } else {
            log = nil
        }
    }

    public func store(_ entry: HAR.Entry) async {
        entries.append(entry)

        guard let config = configuration else { return }

        switch config.destination {
        case .file(let url):
            var activeLog = log ?? HAR.create()
            activeLog.entries.append(entry)
            log = activeLog

            try? HAR.save(activeLog, to: url)

        case .handler(let handler):
            await handler(entry)

        case .memory:
            break
        }
    }

    public func getEntries() -> [HAR.Entry] {
        entries
    }

    /// Clears the active configuration and any captured entries.
    public func clear() {
        configuration = nil
        entries = []
        log = nil
    }

    /// Records a request/response pair as a HAR entry.
    ///
    /// This method applies matchers and filters from the current configuration
    /// before forwarding the resulting entry to `store(_:)`.
    ///
    /// - Parameters:
    ///   - request: The request to record.
    ///   - response: The response to record.
    ///   - data: The response body data.
    ///   - startTime: The time the request started.
    ///   - duration: The request duration.
    public func recordEntry(
        request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        startTime: Date,
        duration: TimeInterval
    ) async {
        guard let config = configuration else { return }

        if let matchers = config.matchers {
            guard matchers.matches(request) else { return }
        }

        do {
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

            await store(entry)
        } catch {
            print("Replay: Failed to create HAR entry: \(String(describing: error))")
        }
    }
}
