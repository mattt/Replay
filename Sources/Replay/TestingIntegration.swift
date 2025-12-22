import Foundation

#if canImport(Testing)
    @_weakLinked import Testing

    // MARK: - Replay Test Trait

    /// A Swift Testing trait that enables Replay for the duration of a test or suite.
    ///
    /// By default, Replay runs in playback-only mode and will fail if the archive is missing.
    /// Recording is an explicit action, enabled via `REPLAY_MODE=record` (or `REPLAY_RECORDING=1`).
    ///
    /// To run the test against the live network (ignoring fixtures and without recording),
    /// set `REPLAY_MODE=live` (or `REPLAY_LIVE=1`).
    public struct ReplayTrait: TestTrait, SuiteTrait, TestScoping {
        private let archiveName: String?
        private let stubs: [Stub]?
        private let matchers: [Matcher]
        private let filters: [Filter]
        private let directory: String
        private let rootURL: URL?
        private let scope: ReplayScope

        public init(
            _ name: String? = nil,
            matchers: [Matcher] = .default,
            filters: [Filter] = [],
            directory: String = "Replays",
            rootURL: URL? = nil,
            stubs: [Stub]? = nil,
            scope: ReplayScope = .global
        ) {
            self.archiveName = name
            self.stubs = stubs
            self.matchers = matchers
            self.filters = filters
            self.directory = directory
            self.rootURL = rootURL
            self.scope = scope
        }

        public func provideScope(
            for test: Test,
            testCase: Test.Case?,
            performing function: @Sendable () async throws -> Void
        ) async throws {
            switch scope {
            case .global:
                try await PlaybackIsolationLock.shared.withLock {
                    try await provideScopeGlobal(for: test, testCase: testCase, performing: function)
                }
            case .test:
                try await provideScopeLocal(for: test, testCase: testCase, performing: function)
            }
        }

        private func provideScopeGlobal(
            for test: Test,
            testCase: Test.Case?,
            performing function: @Sendable () async throws -> Void
        ) async throws {
            let name = archiveName ?? generateArchiveName(for: test, testCase: testCase)
            let archiveURL = try await getArchiveURL(name: name)

            let mode = RecordingMode.current
            let archiveExists = FileManager.default.fileExists(atPath: archiveURL.path)

            let testName = test.displayName ?? test.name

            if stubs == nil, !archiveExists && mode == .playback {
                let instructions = """
                    To record this test's HTTP traffic, run:
                      env REPLAY_MODE=record swift test --filter \(testName)

                    To run against the live network (skip replay + no recording), run:
                      env REPLAY_MODE=live swift test --filter \(testName)
                    """

                throw ReplayError.archiveMissing(
                    path: archiveURL,
                    testName: testName,
                    instructions: instructions
                )
            }

            let playbackMode: PlaybackConfiguration.Mode
            let source: PlaybackConfiguration.Source

            if mode == .live {
                // Live mode: ignore fixtures entirely, pass through to network, and do not record.
                playbackMode = .passthrough
                source = .entries([])
            } else {
                playbackMode = (stubs == nil && mode == .record) ? .record : .strict
                source = stubs.map { .stubs($0) } ?? .file(archiveURL)
            }

            let config = PlaybackConfiguration(
                source: source,
                mode: playbackMode,
                matchers: matchers,
                filters: filters
            )

            // Register URLProtocol globally for zero-config interception.
            URLProtocol.registerClass(PlaybackURLProtocol.self)

            // Configure playback store.
            try await PlaybackStore.shared.configure(config)

            defer {
                URLProtocol.unregisterClass(PlaybackURLProtocol.self)
            }

            do {
                try await function()

                if mode == .record {
                    print("✓ Recorded HTTP traffic to: \(archiveURL.path)")
                }
            } catch {
                await attachDebugInfo(test: test, archiveURL: archiveURL, error: error, store: .shared)
                throw error
            }
        }

        private func provideScopeLocal(
            for test: Test,
            testCase: Test.Case?,
            performing function: @Sendable () async throws -> Void
        ) async throws {
            let name = archiveName ?? generateArchiveName(for: test, testCase: testCase)
            let archiveURL = try await getArchiveURL(name: name)

            let mode = RecordingMode.current
            let archiveExists = FileManager.default.fileExists(atPath: archiveURL.path)

            let testName = test.displayName ?? test.name

            if stubs == nil, !archiveExists && mode == .playback {
                let instructions = """
                    To record this test's HTTP traffic, run:
                      env REPLAY_MODE=record swift test --filter \(testName)

                    To run against the live network (skip replay + no recording), run:
                      env REPLAY_MODE=live swift test --filter \(testName)
                    """

                throw ReplayError.archiveMissing(
                    path: archiveURL,
                    testName: testName,
                    instructions: instructions
                )
            }

            let playbackMode: PlaybackConfiguration.Mode
            let source: PlaybackConfiguration.Source

            if mode == .live {
                playbackMode = .passthrough
                source = .entries([])
            } else {
                playbackMode = (stubs == nil && mode == .record) ? .record : .strict
                source = stubs.map { .stubs($0) } ?? .file(archiveURL)
            }

            let config = PlaybackConfiguration(
                source: source,
                mode: playbackMode,
                matchers: matchers,
                filters: filters
            )

            let localStore = PlaybackStore()
            try await localStore.configure(config)

            defer {
                PlaybackStoreRegistry.shared.unregister(key: PlaybackStoreRegistry.key(for: localStore))
                Task { await localStore.clear() }
            }

            do {
                _ = PlaybackStoreRegistry.shared.register(localStore)
                try await ReplayContext.$playbackStore.withValue(localStore) {
                    try await function()
                }

                if mode == .record {
                    print("✓ Recorded HTTP traffic to: \(archiveURL.path)")
                }
            } catch {
                // Attachments/debug info are best-effort; use the local store's entries if possible.
                await attachDebugInfo(test: test, archiveURL: archiveURL, error: error, store: localStore)
                throw error
            }
        }

        private func generateArchiveName(for test: Test, testCase: Test.Case?) -> String {
            let baseName = test.displayName ?? test.name
            return
                baseName
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
        }

        private func getArchiveURL(name: String) async throws -> URL {
            let baseURL: URL
            if let rootURL {
                baseURL = rootURL
            } else if let defaultRootURL = await ReplayTestDefaults.shared.getReplaysRootURL() {
                baseURL = defaultRootURL
            } else {
                let testBundle = Bundle(for: PlaybackURLProtocol.self)
                baseURL =
                    testBundle.resourceURL?
                    .appendingPathComponent(directory) ?? URL(fileURLWithPath: directory)
            }

            if RecordingMode.current == .record {
                try? FileManager.default.createDirectory(
                    at: baseURL, withIntermediateDirectories: true)
            }

            return baseURL.appendingPathComponent("\(name).har")
        }

        private func attachDebugInfo(
            test: Test,
            archiveURL: URL,
            error: Error,
            store: PlaybackStore
        ) async {
            // Attach failed request details
            if case .noMatchingEntry(let method, let url, _) = error as? ReplayError {
                let requestInfo = """
                    Failed Request Details:

                    Method: \(method)
                    URL: \(url)
                    """

                Attachment.record(requestInfo, named: "failed_request.txt")
            }

            // Attach available entries from playback store
            let entries = await store.getAvailableEntries()
            if !entries.isEmpty {
                let lines = entries.enumerated().map { index, entry in
                    "\(index + 1). \(entry.request.method) \(entry.request.url)"
                }

                let summary = """
                    Available Entries in Archive:

                    \(lines.joined(separator: "\n"))

                    Total: \(entries.count) entries
                    """

                Attachment.record(summary, named: "available_entries.txt")
            }
        }
    }

    // MARK: - Trait Convenience

    extension Trait where Self == ReplayTrait {
        /// Use Replay with auto-generated name from test.
        public static var replay: Self { Self() }

        /// Use Replay with specific archive name.
        public static func replay(_ name: String) -> Self { Self(name) }

        /// Use Replay with custom matching configuration.
        public static func replay(
            _ name: String? = nil,
            matching matchers: [Matcher]
        ) -> Self {
            return Self(name, matchers: matchers)
        }

        /// Use Replay with custom matching configuration and filters.
        public static func replay(
            _ name: String? = nil,
            matching matchers: [Matcher],
            filters: [Filter],
            directory: String = "Replays",
            rootURL: URL? = nil,
            scope: ReplayScope = .global
        ) -> Self {
            return Self(
                name,
                matchers: matchers,
                filters: filters,
                directory: directory,
                rootURL: rootURL,
                scope: scope
            )
        }

        /// Use Replay with in-memory stubs (no HAR file).
        public static func replay(
            stubs: [Stub],
            matching matchers: [Matcher] = .default,
            filters: [Filter] = [],
            directory: String = "Replays",
            rootURL: URL? = nil,
            scope: ReplayScope = .global
        ) -> Self {
            return Self(
                nil,
                matchers: matchers.isEmpty ? .default : matchers,
                filters: filters,
                directory: directory,
                rootURL: rootURL,
                stubs: stubs,
                scope: scope
            )
        }
    }

    // MARK: - Playback Isolation for Tests

    /// Default configuration for `ReplayTrait` archive resolution.
    private actor ReplayTestDefaults {
        static let shared = ReplayTestDefaults()

        private var replaysRootURL: URL?

        func getReplaysRootURL() -> URL? {
            replaysRootURL
        }

        func setReplaysRootURL(_ url: URL?) {
            replaysRootURL = url
        }
    }

    /// Global async lock for tests that use `Playback`.
    ///
    /// This provides mutual exclusion across async test execution to prevent
    /// interference between parallel suites that share `PlaybackStore` and
    /// `PlaybackURLProtocol` global state.
    private actor PlaybackIsolationLock {
        static let shared = PlaybackIsolationLock()

        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isLocked = false

        private init() {}

        private enum Context {
            @TaskLocal
            static var isHeld: Bool = false
        }

        private func acquire() async {
            if isLocked {
                await withCheckedContinuation { continuation in
                    waiters.append(continuation)
                }
            } else {
                isLocked = true
            }
        }

        private func release() {
            if let next = waiters.first {
                waiters.removeFirst()
                next.resume()
            } else {
                isLocked = false
            }
        }

        func withLock<T: Sendable>(
            _ operation: @Sendable () async throws -> T
        ) async rethrows -> T {
            // Avoid deadlocks when a test already holds the lock (e.g. when
            // `ReplayTrait` is used alongside `PlaybackIsolationTrait`).
            if Context.isHeld {
                return try await operation()
            }

            await acquire()
            do {
                let result = try await Context.$isHeld.withValue(true) {
                    try await operation()
                }
                release()
                return result
            } catch {
                release()
                throw error
            }
        }
    }

    /// A test trait that serializes all tests using Replay playback.
    ///
    /// Apply this trait to any suite or test that touches `Playback` to ensure
    /// there is no cross-suite interference through global URLProtocol or
    /// shared `PlaybackStore` state.
    ///
    /// Note: `ReplayTrait` already applies global isolation automatically. This trait is still
    /// useful when you need to override the archive root location (e.g. `Bundle.module`).
    public struct PlaybackIsolationTrait: TestTrait, SuiteTrait, TestScoping {
        private let replaysRootURL: URL?

        public init() {
            self.replaysRootURL = nil
        }

        public init(replaysRootURL: URL?) {
            self.replaysRootURL = replaysRootURL
        }

        public init(replaysFrom bundle: Bundle, subdirectory: String = "Replays") {
            self.replaysRootURL = bundle.resourceURL?.appendingPathComponent(subdirectory)
        }

        public func provideScope(
            for test: Test,
            testCase: Test.Case?,
            performing function: @Sendable () async throws -> Void
        ) async throws {
            try await PlaybackIsolationLock.shared.withLock {
                let defaults = ReplayTestDefaults.shared
                let previousReplaysRootURL = await defaults.getReplaysRootURL()

                if let replaysRootURL {
                    await defaults.setReplaysRootURL(replaysRootURL)
                }

                do {
                    try await function()
                    await defaults.setReplaysRootURL(previousReplaysRootURL)
                } catch {
                    await defaults.setReplaysRootURL(previousReplaysRootURL)
                    throw error
                }
            }
        }
    }

    extension Trait where Self == PlaybackIsolationTrait {
        public static var playbackIsolated: Self { Self() }

        public static func playbackIsolated(
            replaysFrom bundle: Bundle,
            subdirectory: String = "Replays"
        ) -> Self {
            Self(replaysFrom: bundle, subdirectory: subdirectory)
        }

        public static func playbackIsolated(replaysRootURL: URL?) -> Self {
            Self(replaysRootURL: replaysRootURL)
        }
    }

#endif  // canImport(Testing)
