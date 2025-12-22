import Foundation

// MARK: - Playback Configuration

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

public enum ReplayScope: Sendable {
    /// Uses global `URLProtocol.registerClass(...)` and `PlaybackStore.shared`.
    case global

    /// Uses an isolated `PlaybackStore` for the current test/task only.
    ///
    /// Note: This requires using a `URLSession` configured with `PlaybackURLProtocol`
    /// (for example, `Replay.session`).
    case test
}

public struct PlaybackConfiguration: Sendable {
    public let source: Source
    public let mode: Mode
    public let matchers: [Matcher]
    public let filters: [Filter]

    public enum Source: Sendable {
        case file(URL)
        case log(HAR.Log)
        case entries([HAR.Entry])
        case stubs([Stub])
    }

    public enum Mode: Sendable {
        /// Replay from archive; throw error on no match.
        case strict
        /// Replay from archive; pass through to network on no match.
        case passthrough
        /// Replay from archive; record new requests and append to archive.
        case record
    }

    public init(
        source: Source,
        mode: Mode = .strict,
        matchers: [Matcher] = .default,
        filters: [Filter] = []
    ) {
        self.source = source
        self.mode = mode
        self.matchers = matchers
        self.filters = filters
    }
}

// MARK: - Playback URLProtocol

/// Wrapper to send non-Sendable values across isolation boundaries when safety is guaranteed.
private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
}

public final class PlaybackURLProtocol: URLProtocol {
    private static let handledKey = "ReplayPlaybackHandled"

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
        Task {
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

                let (response, data) = try await store.handleRequest(matchingRequest)
                self.client?.urlProtocol(
                    self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    public override func stopLoading() {}
}

// MARK: - Playback Store

public actor PlaybackStore {
    public static let shared = PlaybackStore()

    private var configuration: PlaybackConfiguration?
    private var entries: [HAR.Entry] = []

    public func configure(_ config: PlaybackConfiguration) async throws {
        configuration = config

        switch config.source {
        case .file(let url):
            do {
                let log = try HAR.load(from: url)
                entries = log.entries
            } catch {
                // For record/passthrough workflows, missing archives should not be fatal.
                // Strict playback should still surface missing files as an error.
                switch config.mode {
                case .record, .passthrough:
                    entries = []
                case .strict:
                    throw error
                }
            }

        case .log(let log):
            entries = log.entries

        case .entries(let provided):
            entries = provided

        case .stubs(let stubs):
            entries = try stubs.map { stub in
                try makeEntry(from: stub)
            }
        }
    }

    /// Expose entries for debugging/attachments.
    public func getAvailableEntries() -> [HAR.Entry] {
        entries
    }

    public func handleRequest(_ request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        guard let config = configuration else {
            throw ReplayError.notConfigured
        }

        if let entry = config.matchers.firstMatch(for: request, in: entries) {
            return try entry.toURLResponse()
        }

        switch config.mode {
        case .strict:
            throw ReplayError.noMatchingEntry(
                method: request.httpMethod ?? "GET",
                url: request.url?.absoluteString ?? "unknown",
                archivePath: archivePathDescription(for: config.source)
            )

        case .passthrough:
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReplayError.invalidResponse
            }
            return (httpResponse, data)

        case .record:
            let startTime = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReplayError.invalidResponse
            }
            let duration = Date().timeIntervalSince(startTime)

            var entry = try HAR.Entry(
                request: request,
                response: httpResponse,
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

            return (httpResponse, data)
        }
    }

    public func clear() {
        configuration = nil
        entries = []
    }

    private func archivePathDescription(for source: PlaybackConfiguration.Source) -> String {
        switch source {
        case .file(let url):
            return url.path
        case .log:
            return "<in-memory-log>"
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

// MARK: - Playback Session Factory

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

        try await PlaybackStore.shared.configure(configuration)

        return URLSession(configuration: config)
    }

    /// Clear playback state.
    public static func clear() async {
        await PlaybackStore.shared.clear()
    }
}
