import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

import Testing

@testable import Replay

// MARK: - Example Domain Models

struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

struct Post: Codable {
    let id: Int
    let title: String
    let authorId: Int
}

// MARK: - Example API Client

/// A simple API client that demonstrates how Replay integrates with real code.
actor ExampleAPIClient {
    static let shared = ExampleAPIClient()

    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = URL(string: "https://api.example.com")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchUser(id: Int) async throws -> User {
        let url = baseURL.appendingPathComponent("users/\(id)")
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(User.self, from: data)
    }

    func fetchPosts() async throws -> [Post] {
        let url = baseURL.appendingPathComponent("posts")
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode([Post].self, from: data)
    }

    func createPost(title: String, authorId: Int) async throws -> Post {
        let url = baseURL.appendingPathComponent("posts")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["title": title, "authorId": "\(authorId)"])

        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(Post.self, from: data)
    }
}

// MARK: - Tests Using @Test(.replay)

/// These tests demonstrate the intended usage of Replay for HTTP mocking.
///
/// Each test uses a pre-recorded HAR archive from `Tests/ReplayTests/Replays/`.
/// The archives contain recorded HTTP request/response pairs that are replayed
/// during test execution, eliminating network dependencies.
///
/// To record new fixtures for real APIs:
/// ```
/// env REPLAY_RECORD_MODE=rewrite swift test --filter ExampleAPITests
/// ```
@Suite("Example API Tests", .serialized, .playbackIsolated(replaysFrom: Bundle.module))
struct ExampleAPITests {
    /// Test fetching a single user.
    ///
    /// Uses: `Replays/fetchUser.har`
    @Test(.replay("fetchUser", matching: [.method, .path]))
    func fetchUser() async throws {
        let client = ExampleAPIClient.shared
        let user = try await client.fetchUser(id: 42)

        #expect(user.id == 42)
        #expect(user.name == "Alice")
        #expect(user.email == "alice@example.com")
    }

    /// Test fetching a list of posts.
    ///
    /// Uses: `Replays/fetchPosts.har`
    @Test(.replay("fetchPosts", matching: [.method, .path]))
    func fetchPosts() async throws {
        let client = ExampleAPIClient.shared
        let posts = try await client.fetchPosts()

        #expect(posts.count == 3)
        #expect(posts[0].title == "Hello World")
        #expect(posts[1].title == "Swift Testing")
    }

    /// Test creating a new post via POST request.
    ///
    /// Uses: `Replays/fetchPosts.har` (contains both GET and POST entries)
    @Test(.replay("fetchPosts", matching: [.method, .path]))
    func createPost() async throws {
        let client = ExampleAPIClient.shared
        let post = try await client.createPost(title: "New Post", authorId: 42)

        #expect(post.id == 4)
        #expect(post.title == "New Post")
        #expect(post.authorId == 42)
    }

    /// Demonstrates using filters to redact sensitive data during recording.
    @Test(
        .replay(
            "fetchUser",
            matching: [.method, .path],
            filters: [
                .headers(removing: ["Authorization", "Cookie"]),
                .queryParameters(removing: ["api_key", "token"]),
            ]
        )
    )
    func fetchUserWithFilters() async throws {
        let client = ExampleAPIClient.shared
        let user = try await client.fetchUser(id: 42)

        #expect(user.name == "Alice")
    }

    /// Test fetching a user using in-memory stubs.
    ///
    /// Uses: In-memory stubs instead of a HAR file
    @Test(
        .replay(
            stubs: [
                .get(
                    "https://api.example.com/users/42",
                    200,
                    ["Content-Type": "application/json"],
                    {
                        """
                        {
                            "id": 42,
                            "name": "Alice",
                            "email": "alice@example.com"
                        }
                        """
                    }
                )
            ],
            matching: [.method, .path]
        )
    )
    func fetchUserFromStubs() async throws {
        let client = ExampleAPIClient.shared
        let user = try await client.fetchUser(id: 42)

        #expect(user.id == 42)
        #expect(user.name == "Alice")
        #expect(user.email == "alice@example.com")
    }

    @Test("Missing archive provides helpful error message")
    func missingArchiveError() async throws {
        // Force playback mode so this test is stable even when the overall test run
        // is configured for recording or live network.
        let previousRecord = getenv("REPLAY_RECORD_MODE").map { String(cString: $0) }
        let previousPlayback = getenv("REPLAY_PLAYBACK_MODE").map { String(cString: $0) }
        setenv("REPLAY_RECORD_MODE", "none", 1)
        setenv("REPLAY_PLAYBACK_MODE", "strict", 1)
        defer {
            if let previousRecord {
                setenv("REPLAY_RECORD_MODE", previousRecord, 1)
            } else {
                unsetenv("REPLAY_RECORD_MODE")
            }

            if let previousPlayback {
                setenv("REPLAY_PLAYBACK_MODE", previousPlayback, 1)
            } else {
                unsetenv("REPLAY_PLAYBACK_MODE")
            }
        }

        let trait = ReplayTrait("this_archive_does_not_exist")

        do {
            try await trait.provideScope(
                for: Test.current!,
                testCase: nil,
                performing: {}
            )
            Issue.record("Expected archiveMissing error")
        } catch let error as ReplayError {
            let description = error.description
            #expect(description.contains("Replay Archive Missing"))
            #expect(description.contains("REPLAY_RECORD_MODE=once"))
        }
    }

    @Test("Unmatched request in strict mode provides helpful error")
    func unmatchedRequestError() async throws {
        let entry = HAR.Entry(
            startedDateTime: Date(),
            time: 100,
            request: HAR.Request(
                method: "GET",
                url: "https://api.example.com/known",
                httpVersion: "HTTP/1.1",
                headers: [],
                bodySize: 0
            ),
            response: HAR.Response(
                status: 200,
                statusText: "OK",
                httpVersion: "HTTP/1.1",
                headers: [],
                content: HAR.Content(size: 2, mimeType: "text/plain", text: "OK"),
                bodySize: 2
            ),
            timings: HAR.Timings(send: 0, wait: 100, receive: 0)
        )

        let config = PlaybackConfiguration(
            source: .entries([entry]),
            playbackMode: .strict,
            recordMode: .none,
            matchers: .default
        )

        do {
            let session = try await Playback.session(configuration: config)
            _ = try await session.data(
                from: URL(string: "https://api.example.com/unknown")!)
            Issue.record("Expected noMatchingEntry error")
        } catch let error {
            // URLSession may wrap ReplayError in NSError
            if let replayError = error as? ReplayError {
                // Direct ReplayError
                let description = replayError.description
                #expect(description.contains("No Matching Entry"))
                #expect(description.contains("/unknown"))
            } else if let nsError = error as NSError?,
                nsError.domain == "Replay.ReplayError"
            {
                // URLSession wrapped the error - verify it's a ReplayError
                #expect(nsError.domain == "Replay.ReplayError")
                #expect(nsError.localizedDescription == "No Matching Entry")
                // Verify the detailed message is in failureReason
                #expect(nsError.localizedFailureReason?.contains("No Matching Entry") == true)
                #expect(nsError.localizedFailureReason?.contains("/unknown") == true)
            } else {
                throw error  // Not a ReplayError, re-throw
            }
        }
    }
}

// MARK: - Suite without .playbackIsolated

@Suite("Example API Tests Without Playback Isolated", .serialized)
struct ExampleAPITestsWithoutPlaybackIsolated {
    /// Test fetching a single user.
    ///
    /// Uses: `Replays/fetchUser.har`
    @Test("Fetch User Without Playback Isolated", .replay("fetchUser"))
    func fetchUser() async throws {
        let client = ExampleAPIClient.shared
        let user = try await client.fetchUser(id: 42)

        #expect(user.id == 42)
        #expect(user.name == "Alice")
        #expect(user.email == "alice@example.com")
    }
}

// MARK: - Test without Suite
@Test("Fetch User Without Suite", .replay("fetchUser"))
func fetchUserWithoutSuite() async throws {
    let client = ExampleAPIClient.shared
    let user = try await client.fetchUser(id: 42)

    #expect(user.id == 42)
    #expect(user.name == "Alice")
    #expect(user.email == "alice@example.com")
}
