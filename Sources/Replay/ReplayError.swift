import Foundation

/// Errors thrown by Replay during capture, playback, and testing.
public enum ReplayError: Error, Sendable, CustomStringConvertible, LocalizedError {
    /// Replay has not been configured (e.g. PlaybackStore missing configuration).
    case notConfigured

    /// No matching entry was found for a request in a given archive.
    case noMatchingEntry(method: String, url: String, archivePath: String)

    /// Invalid request construction or conversion.
    case invalidRequest(String)

    /// Received a non-HTTP response.
    case invalidResponse

    /// Invalid URL string.
    case invalidURL(String)

    /// Failed to decode base64 body text.
    case invalidBase64(String)

    /// HAR archive not found at expected URL.
    case archiveNotFound(URL)

    /// Expected replay archive is missing for a test.
    case archiveMissing(path: URL, testName: String, instructions: String)

    public var description: String {
        switch self {
        case .notConfigured:
            return "Replay not configured. Call Playback.session() or use @Test(.replay) trait."

        case .noMatchingEntry(let method, let url, let archivePath):
            return """

                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                ⚠️  No Matching Entry in Archive
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                Request: \(method) \(url)
                Archive: \(archivePath)

                This request was not found in the replay archive.

                Options:
                1. Update the archive with new requests:
                   swift test --filter <test-name> --enable-replay-recording

                2. Check if request details changed (URL, method, headers)
                   and update test expectations

                3. Inspect the archive:
                   replay inspect \(archivePath)
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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
        }
    }

    public var errorDescription: String? {
        description
    }
}
