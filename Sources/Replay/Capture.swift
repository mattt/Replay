import Foundation

/// The Capture API records live HTTP traffic into HAR entries.
///
/// This is intentionally independent of `@Test(.replay)` so it can be used for:
/// - Recording traffic from tooling or sample apps (outside of tests)
/// - Custom recording workflows (e.g. streaming entries to a handler)
/// - Exporting traffic to HAR for use in external tools
///
/// For test recording/playback, prefer `ReplayTrait` (`@Test(.replay)`) and
/// enable recording explicitly with `REPLAY_RECORD=1` or `--enable-replay-recording`.

// MARK: - Capture Configuration

public struct CaptureConfiguration: Sendable {
    public let destination: Destination
    public let filters: [Filter]
    public let matchers: [Matcher]?  // Optional: only capture matching requests

    public enum Destination: Sendable {
        case file(URL)
        case handler(@Sendable (HAR.Entry) async -> Void)
        case memory  // Store in memory for inspection
    }

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

public final class CaptureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "ReplayCaptureHandled"

    private var startTime: Date?
    private var dataTask: URLSessionDataTask?

    public override class func canInit(with request: URLRequest) -> Bool {
        // Prevent infinite loops
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }

        // If there is no configuration yet, we don't capture.
        // The matcher, when present, is consulted asynchronously.
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

    private func shouldCapture(_ request: URLRequest) async -> Bool {
        guard let config = await CaptureStore.shared.currentConfiguration else {
            return false
        }

        if let matchers = config.matchers {
            return matchers.matches(request)
        }

        return true
    }

    @Sendable
    private func recordEntry(
        request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        startTime: Date,
        duration: TimeInterval
    ) async {
        guard await shouldCapture(request) else { return }

        do {
            var entry = try HAR.Entry(
                request: request,
                response: response,
                data: data,
                startTime: startTime,
                duration: duration
            )

            if let config = await CaptureStore.shared.currentConfiguration {
                for filter in config.filters {
                    entry = await filter.apply(to: entry)
                }
            }

            await CaptureStore.shared.store(entry)
        } catch {
            // Intentionally avoid throwing from URLProtocol; log only.
            NSLog("Replay: Failed to create HAR entry: \(String(describing: error))")
        }
    }
}

// MARK: - Capture Store (Actor for thread safety)

public actor CaptureStore {
    public static let shared = CaptureStore()

    private var configuration: CaptureConfiguration?
    private var entries: [HAR.Entry] = []
    private var log: HAR.Log?

    var currentConfiguration: CaptureConfiguration? { configuration }

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

    public func clear() {
        configuration = nil
        entries = []
        log = nil
    }

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

// MARK: - Capture Session Factory

public enum Capture {
    /// Create a `URLSession` configured for capturing HTTP traffic.
    public static func session(
        configuration: CaptureConfiguration,
        baseConfiguration: URLSessionConfiguration = .default
    ) -> URLSession {
        let config = baseConfiguration
        var protocols = config.protocolClasses ?? []
        protocols.insert(CaptureURLProtocol.self, at: 0)
        config.protocolClasses = protocols

        Task {
            await CaptureStore.shared.configure(configuration)
        }

        return URLSession(configuration: config)
    }

    /// Captured entries (when using `.memory` destination).
    public static var entries: [HAR.Entry] {
        get async {
            await CaptureStore.shared.getEntries()
        }
    }

    /// Clear captured data.
    public static func clear() async {
        await CaptureStore.shared.clear()
    }
}
