import Foundation

private func replayEnv(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

/// Namespace for URLSession-related helpers used with Replay.
public enum Replay {
    /// Controls fixture recording behavior for tests and tooling.
    ///
    /// This is driven by the `REPLAY_RECORD_MODE` environment variable.
    public enum RecordMode: String, Hashable, CaseIterable, Sendable {
        /// Do not record (default).
        case none

        /// Record only when the archive is missing.
        case once

        /// Rewrite the archive from scratch each run.
        case rewrite

        /// Gets the record mode from environment variables.
        ///
        /// - Returns: The mode from `REPLAY_RECORD_MODE` environment variable.
        /// - Throws: `ReplayError.invalidRecordingMode` if `REPLAY_RECORD_MODE` is set to an invalid value.
        ///
        ///   Valid values for `REPLAY_RECORD_MODE`: `none`, `once`, `rewrite`.
        ///   If `REPLAY_RECORD_MODE` is not set, returns `.none`.
        public static func fromEnvironment() throws -> RecordMode {
            guard let modeString = replayEnv("REPLAY_RECORD_MODE") else {
                return .none
            }

            guard let mode = RecordMode(rawValue: modeString) else {
                throw ReplayError.invalidRecordingMode(modeString)
            }

            return mode
        }
    }

    /// Controls how recorded fixtures are used (and whether the network is allowed).
    ///
    /// This is driven by the `REPLAY_PLAYBACK_MODE` environment variable.
    public enum PlaybackMode: String, Hashable, CaseIterable, Sendable {
        /// Require fixtures; fail if missing/unmatched (default).
        case strict

        /// Use fixtures when available; otherwise hit the network.
        case passthrough

        /// Ignore fixtures and always hit the network.
        case live

        /// Gets the playback mode from environment variables.
        ///
        /// - Returns: The mode from `REPLAY_PLAYBACK_MODE` environment variable.
        /// - Throws: `ReplayError.invalidRecordingMode` if `REPLAY_PLAYBACK_MODE` is set to an invalid value.
        ///
        ///   Valid values for `REPLAY_PLAYBACK_MODE`: `strict`, `passthrough`, `live`.
        ///   If `REPLAY_PLAYBACK_MODE` is not set, returns `.strict`.
        public static func fromEnvironment() throws -> PlaybackMode {
            guard let value = replayEnv("REPLAY_PLAYBACK_MODE") else {
                return .strict
            }

            guard let mode = PlaybackMode(rawValue: value) else {
                throw ReplayError.invalidRecordingMode(value)
            }

            return mode
        }
    }

    /// A pre-configured `URLSession` with Replay enabled.
    ///
    /// This is a convenience for tests and tools that want a session without
    /// manually configuring `URLSessionConfiguration`.
    public static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        configure(config)

        // When running in `.test` scope, route requests to the scoped store.
        if let store = ReplayContext.playbackStore {
            let key = PlaybackStoreRegistry.key(for: store)
            var headers = config.httpAdditionalHeaders ?? [:]
            headers[ReplayProtocolContext.headerName] = key
            config.httpAdditionalHeaders = headers
        }

        return URLSession(configuration: config)
    }

    /// Configure a `URLSessionConfiguration` with `PlaybackURLProtocol`
    /// inserted at highest priority.
    public static func configure(_ configuration: URLSessionConfiguration) {
        var protocols = configuration.protocolClasses ?? []
        if !protocols.contains(where: { $0 == PlaybackURLProtocol.self }) {
            protocols.insert(PlaybackURLProtocol.self, at: 0)
        }
        configuration.protocolClasses = protocols
    }

    /// Create a new `URLSessionConfiguration` with Replay pre-configured.
    public static func configuration(
        base: URLSessionConfiguration = .default
    ) -> URLSessionConfiguration {
        let config = base
        configure(config)
        return config
    }

    /// Create a `URLSession` with Replay pre-configured.
    public static func makeSession(
        configuration: URLSessionConfiguration = .default
    ) -> URLSession {
        let config = self.configuration(base: configuration)

        if let store = ReplayContext.playbackStore {
            let key = PlaybackStoreRegistry.key(for: store)
            var headers = config.httpAdditionalHeaders ?? [:]
            headers[ReplayProtocolContext.headerName] = key
            config.httpAdditionalHeaders = headers
        }

        return URLSession(configuration: config)
    }
}
