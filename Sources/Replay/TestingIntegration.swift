import Foundation

/// Determines how Replay should behave in tests.
public enum RecordingMode: String, Hashable, CaseIterable {
    /// Only replay from archives (default).
    case playback

    /// Explicitly requested recording.
    case record

    /// Run tests against the live network, ignoring replay archives and without recording.
    case live

    /// Gets the recording mode from environment variables.
    ///
    /// - Returns: The recording mode from `REPLAY_MODE` environment variable.
    /// - Throws: `ReplayError.invalidRecordingMode` if `REPLAY_MODE` is set to an invalid value.
    ///
    ///   Valid values for `REPLAY_MODE`: `playback`, `record`, `live`.
    ///   If `REPLAY_MODE` is not set, returns `.playback`.
    public static func fromEnvironment() throws -> RecordingMode {
        guard
            let modeString = ProcessInfo.processInfo.environment["REPLAY_MODE"]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
        else {
            return .playback
        }

        guard let mode = RecordingMode(rawValue: modeString) else {
            throw ReplayError.invalidRecordingMode(modeString)
        }

        return mode
    }
}

#if canImport(Testing)
    @_weakLinked import Testing

    // MARK: - Replay Test Trait

    /// A Swift Testing trait that enables Replay for the duration of a test or suite.
    ///
    /// By default, Replay runs in playback-only mode and will fail if the archive is missing.
    /// Recording is an explicit action, enabled via `REPLAY_MODE=record`.
    ///
    /// To run the test against the live network (ignoring fixtures and without recording),
    /// set `REPLAY_MODE=live`.
    ///
    /// Valid values for `REPLAY_MODE`: `playback`, `record`, `live`.
    public struct ReplayTrait: TestTrait, SuiteTrait, TestScoping {
        private let archiveName: String?
        private let stubs: [Stub]?
        private let matchers: [Matcher]
        private let filters: [Filter]
        private let directory: String
        private let rootURL: URL?
        private let scope: ReplayScope

        /// Creates a Replay trait for a test or suite.
        ///
        /// By default,
        /// the archive name is derived from the test name,
        /// and Replay runs in playback-only mode
        /// (unless recording or live mode is explicitly enabled).
        ///
        /// - Parameters:
        ///   - name: The HAR archive name (without extension).
        ///     When `nil`,
        ///     Replay derives a name from the test.
        ///   - matchers: Matchers used to match incoming requests to recorded entries.
        ///   - filters: Filters applied to entries when recording.
        ///   - directory: The directory used to locate archives
        ///     (relative to the test source file when available).
        ///   - rootURL: An optional override for the archive root directory.
        ///   - stubs: In-memory stubs to use instead of a HAR file.
        ///   - scope: The replay scope.
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
            let archiveURL = try await getArchiveURL(name: name, test: test)

            let mode = try RecordingMode.fromEnvironment()
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
            defer {
                URLProtocol.unregisterClass(PlaybackURLProtocol.self)
            }

            // Configure playback store.
            try await PlaybackStore.shared.configure(config)

            try await function()

            if mode == .record {
                print("✓ Recorded HTTP traffic to: \(archiveURL.path)")
            }
        }

        private func provideScopeLocal(
            for test: Test,
            testCase: Test.Case?,
            performing function: @Sendable () async throws -> Void
        ) async throws {
            let name = archiveName ?? generateArchiveName(for: test, testCase: testCase)
            let archiveURL = try await getArchiveURL(name: name, test: test)

            let mode = try RecordingMode.fromEnvironment()
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

            _ = PlaybackStoreRegistry.shared.register(localStore)
            try await ReplayContext.$playbackStore.withValue(localStore) {
                try await function()
            }

            if mode == .record {
                print("✓ Recorded HTTP traffic to: \(archiveURL.path)")
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

        /// Normalizes an archive name by removing the `.har` extension if present.
        ///
        /// - Parameter name: The archive name, optionally including `.har` extension.
        /// - Returns: The archive name without the `.har` extension.
        private func normalizeArchiveName(_ name: String) -> String {
            if name.hasSuffix(".har") {
                return String(name.dropLast(4))
            }
            return name
        }

        private func getArchiveURL(name: String, test: Test) async throws -> URL {
            let normalizedName = normalizeArchiveName(name)
            // 1. Check explicit override from IsolationTrait or defaults
            if let rootURL {
                return rootURL.appendingPathComponent("\(normalizedName).har")
            }
            if let defaultRootURL = await ReplayTestDefaults.shared.getReplaysRootURL() {
                return defaultRootURL.appendingPathComponent("\(normalizedName).har")
            }

            // 2. Resolve via Source Location (Preferred for local development & recording)
            if let fileID = test.sourceLocation.fileID as String? {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                // Attempt to resolve fileID against common Swift package roots
                let searchRoots = ["Tests", "Sources"]

                for root in searchRoots {
                    let candidateSource = cwd.appendingPathComponent(root).appendingPathComponent(fileID)
                    if FileManager.default.fileExists(atPath: candidateSource.path) {
                        // Found the test source file. Resolve 'Replays' directory relative to it.
                        let archiveURL =
                            candidateSource
                            .deletingLastPathComponent()  // File directory
                            .appendingPathComponent(directory)  // "Replays"
                            .appendingPathComponent("\(normalizedName).har")

                        // If recording, use this source-relative path
                        if (try? RecordingMode.fromEnvironment()) == .record {
                            try? FileManager.default.createDirectory(
                                at: archiveURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true
                            )
                            return archiveURL
                        }

                        // If playback, use it if it exists (faster feedback loop than Bundle copy)
                        if FileManager.default.fileExists(atPath: archiveURL.path) {
                            return archiveURL
                        }
                    }
                }
            }

            // 3. Fallback: Search in Bundles (for CI / copied resources)
            // We search for the directory/name.har combination in all available bundles.
            let bundles = Bundle.allBundles + Bundle.allFrameworks
            for bundle in bundles {
                if let url = bundle.url(
                    forResource: normalizedName, withExtension: "har", subdirectory: directory)
                {
                    return url
                }
            }

            // 4. Fallback to CWD/directory (Old behavior, mostly for Linux or when sourceLocation is missing)
            let cwdURL = URL(fileURLWithPath: directory)
            if (try? RecordingMode.fromEnvironment()) == .record {
                try? FileManager.default.createDirectory(
                    at: cwdURL, withIntermediateDirectories: true)
            }
            return cwdURL.appendingPathComponent("\(normalizedName).har")
        }
    }

    // MARK: - Trait Convenience

    extension Trait where Self == ReplayTrait {
        /// Use Replay with auto-generated name from test.
        public static var replay: Self { Self() }

        /// Uses Replay with a specific archive name.
        ///
        /// - Parameter name: The HAR archive name (with or without `.har` extension).
        public static func replay(_ name: String) -> Self { Self(name) }

        /// Uses Replay with a custom matching configuration.
        ///
        /// - Parameters:
        ///   - name: The HAR archive name (with or without `.har` extension).
        ///     When `nil`,
        ///     Replay derives a name from the test.
        ///   - matchers: Matchers used to match incoming requests to recorded entries.
        public static func replay(
            _ name: String? = nil,
            matching matchers: [Matcher]
        ) -> Self {
            return Self(name, matchers: matchers)
        }

        /// Uses Replay with a custom matching configuration and filters.
        ///
        /// - Parameters:
        ///   - name: The HAR archive name (with or without `.har` extension).
        ///     When `nil`,
        ///     Replay derives a name from the test.
        ///   - matchers: Matchers used to match incoming requests to recorded entries.
        ///   - filters: Filters applied to entries when recording.
        ///   - directory: The directory used to locate archives.
        ///   - rootURL: An optional override for the archive root directory.
        ///   - scope: The replay scope.
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

        /// Uses Replay with in-memory stubs (no HAR file).
        ///
        /// - Parameters:
        ///   - stubs: Stubs used for playback.
        ///   - matchers: Matchers used to match incoming requests to recorded entries.
        ///   - filters: Filters applied to entries when recording.
        ///   - directory: The directory used to locate archives.
        ///   - rootURL: An optional override for the archive root directory.
        ///   - scope: The replay scope.
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

        /// Creates an isolation trait without changing the archive root.
        ///
        /// Use this trait to serialize tests that touch Replay playback,
        /// even when you are not overriding archive resolution.
        public init() {
            self.replaysRootURL = nil
        }

        /// Creates an isolation trait that overrides the replay archive root.
        ///
        /// - Parameter replaysRootURL: The root URL containing replay archives.
        public init(replaysRootURL: URL?) {
            self.replaysRootURL = replaysRootURL
        }

        /// Creates an isolation trait that resolves archives from a bundle resource directory.
        ///
        /// - Parameters:
        ///   - bundle: The bundle containing replay archives.
        ///   - subdirectory: The subdirectory within the bundle's resource directory.
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
        /// Serializes tests using Replay playback.
        public static var playbackIsolated: Self { Self() }

        /// Serializes tests using Replay playback,
        /// resolving archives from a bundle resource directory.
        ///
        /// - Parameters:
        ///   - bundle: The bundle containing replay archives.
        ///   - subdirectory: The subdirectory within the bundle's resource directory.
        public static func playbackIsolated(
            replaysFrom bundle: Bundle,
            subdirectory: String = "Replays"
        ) -> Self {
            Self(replaysFrom: bundle, subdirectory: subdirectory)
        }

        /// Serializes tests using Replay playback,
        /// overriding the archive root URL.
        ///
        /// - Parameter replaysRootURL: The root URL containing replay archives.
        public static func playbackIsolated(replaysRootURL: URL?) -> Self {
            Self(replaysRootURL: replaysRootURL)
        }
    }

#endif  // canImport(Testing)
