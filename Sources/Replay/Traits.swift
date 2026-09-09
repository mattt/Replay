import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(Testing)
    @_weakLinked import Testing

    // MARK: - Replay Test Trait

    /// A Swift Testing trait that enables Replay for the duration of a test or suite.
    ///
    /// By default, Replay runs in playback-only mode and will fail if the archive is missing.
    /// Recording is an explicit action, enabled via `REPLAY_RECORD_MODE`.
    ///
    /// To run the test against the live network (ignoring fixtures),
    /// set `REPLAY_PLAYBACK_MODE=live`.
    ///
    /// Valid values for:
    /// - `REPLAY_RECORD_MODE`: `none`, `once`, `rewrite`
    /// - `REPLAY_PLAYBACK_MODE`: `strict`, `passthrough`, `live`
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

            let recordMode = try Replay.RecordMode.fromEnvironment()
            let playbackMode = try Replay.PlaybackMode.fromEnvironment()
            let archiveExists = FileManager.default.fileExists(atPath: archiveURL.path)

            let testName = test.displayName ?? test.name

            if stubs == nil, !archiveExists, recordMode == .none, playbackMode == .strict {
                let instructions = """
                    To record this test's HTTP traffic (archive missing), run:
                      env REPLAY_RECORD_MODE=once swift test --filter \(testName)

                    To run against the live network (ignore fixtures), run:
                      env REPLAY_PLAYBACK_MODE=live swift test --filter \(testName)
                    """

                throw ReplayError.archiveMissing(
                    path: archiveURL,
                    testName: testName,
                    instructions: instructions
                )
            }

            let (config, didRecord) = try makePlaybackConfiguration(
                recordMode: recordMode,
                playbackMode: playbackMode,
                archiveURL: archiveURL,
                archiveExists: archiveExists
            )

            // Register URLProtocol globally for zero-config interception.
            _ = URLProtocol.registerClass(PlaybackURLProtocol.self)
            defer {
                URLProtocol.unregisterClass(PlaybackURLProtocol.self)
            }

            // Configure playback store.
            try await PlaybackStore.shared.configure(config)

            try await function()

            if didRecord {
                await PlaybackStore.shared.flush()
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

            let recordMode = try Replay.RecordMode.fromEnvironment()
            let playbackMode = try Replay.PlaybackMode.fromEnvironment()
            let archiveExists = FileManager.default.fileExists(atPath: archiveURL.path)

            let testName = test.displayName ?? test.name

            if stubs == nil, !archiveExists, recordMode == .none, playbackMode == .strict {
                let instructions = """
                    To record this test's HTTP traffic (archive missing), run:
                      env REPLAY_RECORD_MODE=once swift test --filter \(testName)

                    To run against the live network (ignore fixtures), run:
                      env REPLAY_PLAYBACK_MODE=live swift test --filter \(testName)
                    """

                throw ReplayError.archiveMissing(
                    path: archiveURL,
                    testName: testName,
                    instructions: instructions
                )
            }

            let (config, didRecord) = try makePlaybackConfiguration(
                recordMode: recordMode,
                playbackMode: playbackMode,
                archiveURL: archiveURL,
                archiveExists: archiveExists
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

            if didRecord {
                await localStore.flush()
                print("✓ Recorded HTTP traffic to: \(archiveURL.path)")
            }
        }

        private func makePlaybackConfiguration(
            recordMode: Replay.RecordMode,
            playbackMode: Replay.PlaybackMode,
            archiveURL: URL,
            archiveExists: Bool
        ) throws -> (PlaybackConfiguration, didRecord: Bool) {
            // Stubs are always deterministic; ignore environment modes.
            if let stubs {
                return (
                    PlaybackConfiguration(
                        source: .stubs(stubs),
                        playbackMode: .strict,
                        recordMode: .none,
                        matchers: matchers,
                        filters: filters
                    ),
                    false
                )
            }

            let didRecord: Bool =
                switch recordMode {
                case .none:
                    false
                case .once:
                    !archiveExists
                case .rewrite:
                    true
                }

            return (
                PlaybackConfiguration(
                    source: .file(archiveURL),
                    playbackMode: playbackMode,
                    recordMode: recordMode,
                    matchers: matchers,
                    filters: filters
                ),
                didRecord
            )
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
            let recordMode = (try? Replay.RecordMode.fromEnvironment()) ?? .none
            return try await resolveArchiveURL(name: name, test: test, recordMode: recordMode)
        }

        /// Resolves the archive location for a test.
        ///
        /// Resolution order:
        ///
        /// 1. A `rootURL` passed to this trait.
        /// 2. A directory set with `.playbackIsolated(replaysRootURL:)`.
        /// 3. The `Replays/` directory next to the test's source file.
        ///    Recording always writes here when the source file is present,
        ///    and playback reads from here when the archive exists.
        /// 4. A bundle set with `.playbackIsolated(replaysFrom:)`.
        /// 5. Any loaded bundle that contains `Replays/<name>.har` as a resource.
        /// 6. `Replays/` under the current working directory.
        func resolveArchiveURL(name: String, test: Test, recordMode: Replay.RecordMode) async throws -> URL {
            let fileName = "\(normalizeArchiveName(name)).har"
            let isRecording = recordMode != .none

            // 1. Explicit override on the trait.
            if let rootURL {
                return rootURL.appendingPathComponent(fileName)
            }

            // 2. Explicit directory from the isolation trait.
            let defaultRoot = await ReplayTestDefaults.shared.getArchiveRoot()
            if case .directory(let url) = defaultRoot {
                return url.appendingPathComponent(fileName)
            }

            // 3. Next to the test's source file.
            // Bundles are rebuilt on every build, so recording into one loses the archive;
            // the source tree is the only durable destination.
            if let sourceDirectory = Self.sourceDirectory(for: test) {
                let archiveURL =
                    sourceDirectory
                    .appendingPathComponent(directory)
                    .appendingPathComponent(fileName)

                if isRecording {
                    try? FileManager.default.createDirectory(
                        at: archiveURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    return archiveURL
                }

                if FileManager.default.fileExists(atPath: archiveURL.path) {
                    return archiveURL
                }
            }

            // 4. Bundle from the isolation trait (copied resources, typically in CI).
            if case .bundle(let url) = defaultRoot {
                return url.appendingPathComponent(fileName)
            }

            // 5. Any loaded bundle that carries the archive as a resource.
            let bundles = Bundle.allBundles + Bundle.allFrameworks
            for bundle in bundles {
                if let url = bundle.url(
                    forResource: normalizeArchiveName(name), withExtension: "har", subdirectory: directory)
                {
                    return url
                }
            }

            // 6. Current working directory (Linux, or when the source location is unavailable).
            let cwdURL = URL(fileURLWithPath: directory)
            if isRecording {
                try? FileManager.default.createDirectory(
                    at: cwdURL, withIntermediateDirectories: true)
            }
            return cwdURL.appendingPathComponent(fileName)
        }

        /// The directory containing the test's source file,
        /// if that file exists on this machine.
        ///
        /// Swift Testing records the absolute path at compile time,
        /// which is the location to check first.
        /// The `Tests/` and `Sources/` guesses against the working directory
        /// cover test bundles built elsewhere and run from a package checkout.
        private static func sourceDirectory(for test: Test) -> URL? {
            #if compiler(>=6.3)
                let filePath = test.sourceLocation.filePath
            #else
                let filePath = test.sourceLocation._filePath
            #endif

            var candidates = [URL(fileURLWithPath: filePath)]

            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let fileID = test.sourceLocation.fileID
            for root in ["Tests", "Sources"] {
                candidates.append(cwd.appendingPathComponent(root).appendingPathComponent(fileID))
            }

            guard let sourceFile = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            else {
                return nil
            }
            return sourceFile.deletingLastPathComponent()
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

    /// Where `.playbackIsolated` points archive resolution when a test
    /// doesn't say otherwise.
    enum ArchiveRoot: Sendable, Equatable {
        /// A directory chosen by the caller.
        /// Used for playback and recording alike.
        case directory(URL)

        /// A bundle's resource directory.
        /// Used for playback only, after the test's source tree,
        /// because bundles are rebuilt on every build.
        case bundle(URL)
    }

    /// Default configuration for `ReplayTrait` archive resolution.
    private actor ReplayTestDefaults {
        static let shared = ReplayTestDefaults()

        private var archiveRoot: ArchiveRoot?

        func getArchiveRoot() -> ArchiveRoot? {
            archiveRoot
        }

        func setArchiveRoot(_ root: ArchiveRoot?) {
            archiveRoot = root
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
        private let root: ArchiveRoot?

        /// Creates an isolation trait without changing the archive root.
        ///
        /// Use this trait to serialize tests that touch Replay playback,
        /// even when you are not overriding archive resolution.
        public init() {
            self.root = nil
        }

        init(root: ArchiveRoot?) {
            self.root = root
        }

        /// Creates an isolation trait that overrides the replay archive root.
        ///
        /// The directory is used for playback and recording alike.
        ///
        /// - Parameter replaysRootURL: The root URL containing replay archives.
        public init(replaysRootURL: URL?) {
            self.root = replaysRootURL.map { .directory($0) }
        }

        /// Creates an isolation trait that resolves archives from a bundle resource directory.
        ///
        /// The bundle is a playback fallback:
        /// an archive next to the test's source file takes precedence when it exists,
        /// and recording always writes next to the source file
        /// (bundles are rebuilt on every build, so an archive recorded into one is lost).
        ///
        /// - Parameters:
        ///   - bundle: The bundle containing replay archives.
        ///   - subdirectory: The subdirectory within the bundle's resource directory.
        public init(replaysFrom bundle: Bundle, subdirectory: String = "Replays") {
            self.root = bundle.resourceURL.map { .bundle($0.appendingPathComponent(subdirectory)) }
        }

        public func provideScope(
            for test: Test,
            testCase: Test.Case?,
            performing function: @Sendable () async throws -> Void
        ) async throws {
            try await PlaybackIsolationLock.shared.withLock {
                let defaults = ReplayTestDefaults.shared
                let previousRoot = await defaults.getArchiveRoot()

                if let root {
                    await defaults.setArchiveRoot(root)
                }

                do {
                    try await function()
                    await defaults.setArchiveRoot(previousRoot)
                } catch {
                    await defaults.setArchiveRoot(previousRoot)
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
