import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("ReplayError Tests")
struct ReplayErrorTests {

    // MARK: - Error Cases

    @Suite("Error Cases")
    struct ErrorCaseTests {
        @Test("notConfigured error")
        func notConfigured() {
            let error = ReplayError.notConfigured

            #expect(error.description.contains("not configured"))
            #expect(error.description.contains("Playback.session()"))
        }

        @Test("invalidRecordingMode error")
        func invalidRecordingMode() {
            let error = ReplayError.invalidRecordingMode("invalid-mode")

            #expect(error.description.contains("Invalid REPLAY_RECORD_MODE"))
            #expect(error.description.contains("invalid-mode"))
            #expect(error.description.contains("none, once, rewrite"))
        }

        @Test("invalidPlaybackMode error")
        func invalidPlaybackMode() {
            let error = ReplayError.invalidPlaybackMode("invalid-mode")

            #expect(error.description.contains("Invalid REPLAY_PLAYBACK_MODE"))
            #expect(error.description.contains("invalid-mode"))
            #expect(error.description.contains("strict, passthrough, live"))
        }

        @Test("noMatchingEntry error")
        func noMatchingEntry() {
            let error = ReplayError.noMatchingEntry(
                method: "GET",
                url: "https://api.example.com/users",
                archivePath: "/path/to/archive.har"
            )

            #expect(error.description.contains("GET"))
            #expect(error.description.contains("https://api.example.com/users"))
            #expect(error.description.contains("/path/to/archive.har"))
            #expect(error.description.contains("No Matching Entry"))

            #expect(error.errorDescription == "No Matching Entry")
            #expect(error.failureReason?.contains("GET") == true)
        }

        @Test("noMatchingStub error")
        func noMatchingStub() {
            let error = ReplayError.noMatchingStub(
                method: "POST",
                url: "https://api.example.com/users",
                availableStubs: "  • GET https://example.com/api\n  • POST https://example.com/login"
            )

            #expect(error.description.contains("POST"))
            #expect(error.description.contains("https://api.example.com/users"))
            #expect(error.description.contains("No Matching Stub"))
            #expect(error.description.contains("Available Stubs"))
            #expect(error.description.contains("GET https://example.com/api"))

            #expect(error.errorDescription == "No Matching Stub")
            #expect(error.failureReason?.contains("POST") == true)
        }

        @Test("invalidRequest error")
        func invalidRequest() {
            let error = ReplayError.invalidRequest("Missing URL")

            #expect(error.description.contains("Invalid request"))
            #expect(error.description.contains("Missing URL"))
        }

        @Test("invalidResponse error")
        func invalidResponse() {
            let error = ReplayError.invalidResponse

            #expect(error.description.contains("non-HTTP response"))
        }

        @Test("invalidURL error")
        func invalidURL() {
            let error = ReplayError.invalidURL("not a valid url")

            #expect(error.description.contains("Invalid URL"))
            #expect(error.description.contains("not a valid url"))
        }

        @Test("invalidBase64 error")
        func invalidBase64() {
            let error = ReplayError.invalidBase64("not-valid-base64-data")

            #expect(error.description.contains("Failed to decode base64"))
            #expect(error.description.contains("not-valid-base64-data"))
        }

        @Test("invalidBase64 truncates long text")
        func invalidBase64Truncation() {
            let longText = String(repeating: "x", count: 100)
            let error = ReplayError.invalidBase64(longText)

            #expect(error.description.contains("..."))
            #expect(!error.description.contains(longText))
        }

        @Test("archiveNotFound error")
        func archiveNotFound() {
            let url = URL(fileURLWithPath: "/path/to/missing.har")
            let error = ReplayError.archiveNotFound(url)

            #expect(error.description.contains("HAR archive not found"))
            #expect(error.description.contains("/path/to/missing.har"))
        }

        @Test("archiveMissing error")
        func archiveMissing() {
            let url = URL(fileURLWithPath: "/tests/fixtures/test.har")
            let error = ReplayError.archiveMissing(
                path: url,
                testName: "testUserAuthentication",
                instructions: "Run env REPLAY_RECORD_MODE=once swift test --filter testUserAuthentication"
            )

            #expect(error.description.contains("Archive Missing"))
            #expect(error.description.contains("/tests/fixtures/test.har"))
            #expect(error.description.contains("testUserAuthentication"))
            #expect(error.description.contains("REPLAY_RECORD_MODE=once"))
        }
    }

    // MARK: - CustomStringConvertible

    @Suite("CustomStringConvertible")
    struct CustomStringConvertibleTests {
        @Test("description returns non-empty string for all cases")
        func descriptionNonEmpty() {
            let errors: [ReplayError] = [
                .notConfigured,
                .invalidRecordingMode("invalid"),
                .invalidPlaybackMode("invalid"),
                .invalidRequest("test reason"),
                .invalidResponse,
                .invalidURL("bad-url"),
                .invalidBase64("bad-data"),
                .archiveNotFound(URL(fileURLWithPath: "/file.har")),
                .archiveMissing(
                    path: URL(fileURLWithPath: "/file.har"),
                    testName: "test",
                    instructions: "instructions"
                ),
                .noMatchingEntry(method: "POST", url: "https://example.com", archivePath: "/archive.har"),
                .noMatchingStub(
                    method: "GET", url: "https://example.com", availableStubs: "  • GET https://example.com"),
            ]

            for error in errors {
                #expect(!error.description.isEmpty)
            }
        }
    }

    // MARK: - LocalizedError

    @Suite("LocalizedError")
    struct LocalizedErrorTests {
        @Test("errorDescription returns concise summary")
        func errorDescriptionConciseSummary() {
            #expect(ReplayError.notConfigured.errorDescription == "Replay Not Configured")
            #expect(ReplayError.invalidRecordingMode("invalid").errorDescription == "Invalid Recording Mode")
            #expect(ReplayError.invalidPlaybackMode("invalid").errorDescription == "Invalid Playback Mode")
            #expect(ReplayError.invalidRequest("reason").errorDescription == "Invalid Request")
            #expect(ReplayError.invalidResponse.errorDescription == "Invalid Response")
            #expect(ReplayError.invalidURL("url").errorDescription == "Invalid URL")
            #expect(ReplayError.invalidBase64("data").errorDescription == "Invalid Base64")
            #expect(
                ReplayError.archiveNotFound(URL(fileURLWithPath: "/file.har")).errorDescription == "Archive Not Found")
            #expect(
                ReplayError.archiveMissing(
                    path: URL(fileURLWithPath: "/file.har"), testName: "test", instructions: "instructions"
                ).errorDescription == "Archive Missing")
            #expect(
                ReplayError.noMatchingEntry(method: "GET", url: "https://example.com", archivePath: "/archive.har")
                    .errorDescription == "No Matching Entry")
            #expect(
                ReplayError.noMatchingStub(method: "GET", url: "https://example.com", availableStubs: "")
                    .errorDescription == "No Matching Stub")
        }

        @Test("errorDescription is non-nil")
        func errorDescriptionNonNil() {
            let error = ReplayError.notConfigured

            #expect(error.errorDescription != nil)
        }
    }

    // MARK: - Error Protocol Conformance

    @Suite("Error Protocol")
    struct ErrorProtocolTests {
        @Test("can be thrown and caught as Error")
        func throwsAsError() {
            func throwingFunction() throws {
                throw ReplayError.invalidResponse
            }

            #expect(throws: ReplayError.self) {
                try throwingFunction()
            }
        }

        @Test("can be caught as specific error case")
        func catchSpecificCase() {
            do {
                throw ReplayError.invalidURL("test")
            } catch ReplayError.invalidURL(let url) {
                #expect(url == "test")
            } catch {
                Issue.record("Expected invalidURL error")
            }
        }
    }

    // MARK: - CustomNSError

    @Suite("CustomNSError")
    struct CustomNSErrorTests {
        @Test("errorDomain is correct")
        func errorDomain() {
            #expect(ReplayError.errorDomain == "Replay.ReplayError")
        }

        @Test("errorCode is unique for each case")
        func errorCodeUniqueness() {
            let errors: [ReplayError] = [
                .notConfigured,
                .invalidRecordingMode("invalid"),
                .invalidPlaybackMode("invalid"),
                .invalidRequest("reason"),
                .invalidResponse,
                .invalidURL("url"),
                .invalidBase64("data"),
                .archiveNotFound(URL(fileURLWithPath: "/file.har")),
                .archiveMissing(
                    path: URL(fileURLWithPath: "/file.har"),
                    testName: "test",
                    instructions: "instructions"
                ),
                .noMatchingEntry(method: "GET", url: "https://example.com", archivePath: "/archive.har"),
                .noMatchingStub(
                    method: "GET", url: "https://example.com", availableStubs: "  • GET https://example.com"),
            ]

            let codes = Set(errors.map { $0.errorCode })
            #expect(codes.count == errors.count)
        }

        @Test("errorUserInfo contains localized description and failure reason")
        func errorUserInfoContainsDescription() {
            let error = ReplayError.noMatchingEntry(
                method: "GET",
                url: "https://api.example.com/users",
                archivePath: "/path/to/archive.har"
            )

            let userInfo = error.errorUserInfo
            let description = userInfo[NSLocalizedDescriptionKey] as? String
            let failureReason = userInfo[NSLocalizedFailureReasonErrorKey] as? String

            #expect(description == "No Matching Entry")
            #expect(failureReason == error.description)
            #expect(failureReason?.contains("No Matching Entry") == true)
        }

        @Test("bridges to NSError with proper description")
        func bridgesToNSError() {
            let replayError = ReplayError.noMatchingEntry(
                method: "GET",
                url: "https://api.example.com/users?limit=2",
                archivePath: "/path/to/archive.har"
            )

            let nsError = replayError as NSError

            #expect(nsError.domain == "Replay.ReplayError")
            #expect(nsError.code == 9)
            #expect(nsError.localizedDescription == "No Matching Entry")
            #expect(nsError.localizedFailureReason == replayError.description)
            #expect(nsError.localizedFailureReason?.contains("GET") == true)
        }

        @Test("errorCode values match implementation")
        func errorCodeValues() {
            #expect(ReplayError.notConfigured.errorCode == 0)
            #expect(ReplayError.invalidRecordingMode("invalid").errorCode == 1)
            #expect(ReplayError.invalidPlaybackMode("invalid").errorCode == 2)
            #expect(ReplayError.invalidRequest("reason").errorCode == 3)
            #expect(ReplayError.invalidResponse.errorCode == 4)
            #expect(ReplayError.invalidURL("url").errorCode == 5)
            #expect(ReplayError.invalidBase64("data").errorCode == 6)
            #expect(ReplayError.archiveNotFound(URL(fileURLWithPath: "/file.har")).errorCode == 7)
            #expect(
                ReplayError.archiveMissing(
                    path: URL(fileURLWithPath: "/file.har"), testName: "test", instructions: "instructions"
                ).errorCode == 8)
            #expect(
                ReplayError.noMatchingEntry(method: "GET", url: "https://example.com", archivePath: "/archive.har")
                    .errorCode == 9)
            #expect(
                ReplayError.noMatchingStub(method: "GET", url: "https://example.com", availableStubs: "").errorCode
                    == 10
            )
        }
    }

    // MARK: - Sendable

    @Suite("Sendable")
    struct SendableTests {
        @Test("ReplayError is Sendable")
        func isSendable() async {
            let error = ReplayError.notConfigured

            await Task.detached {
                _ = error.description
            }.value
        }
    }
}
