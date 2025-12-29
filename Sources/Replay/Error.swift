import Foundation

/// Errors thrown by Replay during capture, playback, and testing.
public enum ReplayError: Error, Sendable, CustomStringConvertible, LocalizedError, CustomNSError {
    // MARK: - Configuration Errors

    /// Replay has not been configured (e.g. PlaybackStore missing configuration).
    case notConfigured

    /// Invalid replay environment value.
    case invalidRecordingMode(String)

    // MARK: - Validation Errors

    /// Invalid request construction or conversion.
    case invalidRequest(String)

    /// Received a non-HTTP response.
    case invalidResponse

    /// Invalid URL string.
    case invalidURL(String)

    /// Failed to decode base64 body text.
    case invalidBase64(String)

    // MARK: - Archive Errors

    /// HAR archive not found at expected URL.
    case archiveNotFound(URL)

    /// Expected replay archive is missing for a test.
    case archiveMissing(path: URL, testName: String, instructions: String)

    /// No matching entry was found for a request in a given archive.
    case noMatchingEntry(method: String, url: String, archivePath: String)

    // MARK: - Stub Errors

    /// No matching stub was found for a request.
    case noMatchingStub(method: String, url: String, availableStubs: String)

    /// The full formatted error message
    private var formattedMessage: String {
        switch self {
        case .notConfigured:
            return "Replay not configured. Call Playback.session() or use @Test(.replay) trait."

        case .invalidRecordingMode(let value):
            return """
                Invalid Replay configuration value: "\(value)"

                Valid values for:
                  REPLAY_RECORD_MODE: none, once, rewrite
                  REPLAY_PLAYBACK_MODE: strict, passthrough, live
                """

        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"

        case .invalidResponse:
            return "Received non-HTTP response"

        case .invalidURL(let url):
            return "Invalid URL: \(url)"

        case .invalidBase64(let text):
            return "Failed to decode base64: \(text.prefix(50))..."

        case .archiveNotFound(let url):
            return "HAR archive not found at: \(url.path)"

        case .archiveMissing(let path, let testName, let instructions):
            return """

                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                ⚠️  Replay Archive Missing
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                Test: \(testName)
                Expected archive: \(path.path)

                \(instructions)

                Note: Archives are NOT created automatically to prevent
                accidental recording of incorrect responses.
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                """

        case .noMatchingEntry(let method, let url, let archivePath):
            return """

                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                ⚠️  No Matching Entry in Archive
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                Request: \(method) \(url)
                Archive: \(archivePath)

                This request was not found in the replay archive.

                Options:
                1. Run against the live network (ignore fixtures):
                   REPLAY_PLAYBACK_MODE=live swift test --filter <test-name>

                2. Rewrite the archive from scratch:
                   REPLAY_RECORD_MODE=rewrite swift test --filter <test-name>

                3. Check if request details changed (URL, method, headers)
                   and update test expectations

                4. Inspect the archive:
                   swift package replay inspect \(archivePath)
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                """

        case .noMatchingStub(let method, let url, let availableStubs):
            return """

                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                ⚠️  No Matching Stub
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                Request: \(method) \(url)

                Available Stubs:
                \(availableStubs)

                This request did not match any of the provided stubs.

                Options:
                1. Check if the URL or method matches exactly.
                2. Add a new stub for this request.
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                """
        }
    }

    public var description: String {
        formattedMessage
    }

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Replay Not Configured"
        case .invalidRecordingMode:
            return "Invalid Recording Mode"
        case .invalidRequest:
            return "Invalid Request"
        case .invalidResponse:
            return "Invalid Response"
        case .invalidURL:
            return "Invalid URL"
        case .invalidBase64:
            return "Invalid Base64"
        case .archiveNotFound:
            return "Archive Not Found"
        case .archiveMissing:
            return "Archive Missing"
        case .noMatchingEntry:
            return "No Matching Entry"
        case .noMatchingStub:
            return "No Matching Stub"
        }
    }

    public var failureReason: String? {
        formattedMessage
    }

    // MARK: - CustomNSError

    public static var errorDomain: String {
        "Replay.ReplayError"
    }

    public var errorCode: Int {
        switch self {
        case .notConfigured: return 0
        case .invalidRecordingMode: return 1
        case .invalidRequest: return 2
        case .invalidResponse: return 3
        case .invalidURL: return 4
        case .invalidBase64: return 5
        case .archiveNotFound: return 6
        case .archiveMissing: return 7
        case .noMatchingEntry: return 8
        case .noMatchingStub: return 9
        }
    }

    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [:]
        if let errorDescription {
            userInfo[NSLocalizedDescriptionKey] = errorDescription
        }
        if let failureReason {
            userInfo[NSLocalizedFailureReasonErrorKey] = failureReason
        }
        return userInfo
    }
}
