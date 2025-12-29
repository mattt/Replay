import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("ReplayTrait Tests", .serialized, .playbackIsolated)
struct ReplayTraitTests {

    @Test("Trait throws archiveMissing when archive doesn't exist")
    func archiveMissingError() async throws {
        let trait = ReplayTrait("nonexistent_archive", directory: NSTemporaryDirectory())

        await #expect(throws: ReplayError.self) {
            try await trait.provideScope(
                for: Test.current!,
                testCase: nil,
                performing: {}
            )
        }
    }

    // URLProtocol works differently on Linux; these tests rely on Apple-specific behavior
    #if !canImport(FoundationNetworking)
        @Test("Playback from in-memory entries")
        func playbackFromEntries() async throws {
            let entry = makeTestEntry(
                url: "https://api.example.com/users/1",
                method: "GET",
                status: 200,
                body: #"{"id":1,"name":"Test User"}"#
            )

            let config = PlaybackConfiguration(
                source: .entries([entry]),
                playbackMode: .strict,
                recordMode: .none,
                matchers: .default
            )

            let session = try await Playback.session(configuration: config)

            let url = URL(string: "https://api.example.com/users/1")!
            let (data, response) = try await session.data(from: url)

            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 200)

            let json = try #require(String(data: data, encoding: .utf8))
            #expect(json.contains("Test User"))
        }

        @Test("Playback strict mode throws on unmatched request")
        func strictModeThrowsOnMismatch() async throws {
            let entry = makeTestEntry(
                url: "https://api.example.com/users/1",
                method: "GET",
                status: 200,
                body: "{}"
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
                    from: URL(string: "https://api.example.com/users/999")!)
                Issue.record("Expected noMatchingEntry error")
            } catch {
                // URLSession wraps ReplayError in NSError, but LocalizedError preserves description
                let description: String
                if let replayError = error as? ReplayError {
                    description = replayError.description
                } else {
                    description = (error as NSError).localizedDescription
                }

                // Verify it's a ReplayError by checking the description
                #expect(description.contains("No Matching Entry") || description.contains("Replay"))
            }
        }
    #endif

    @Test("Matcher matches by method and URL")
    func matcherMatchesByMethodAndURL() async throws {
        let getEntry = makeTestEntry(
            url: "https://api.example.com/resource",
            method: "GET",
            status: 200,
            body: "GET response"
        )

        let postEntry = makeTestEntry(
            url: "https://api.example.com/resource",
            method: "POST",
            status: 201,
            body: "POST response"
        )

        let matchers: [Matcher] = [.method, .url]

        var getRequest = URLRequest(url: URL(string: "https://api.example.com/resource")!)
        getRequest.httpMethod = "GET"

        var postRequest = URLRequest(url: URL(string: "https://api.example.com/resource")!)
        postRequest.httpMethod = "POST"

        let getMatch = matchers.firstMatch(for: getRequest, in: [getEntry, postEntry])
        #expect(getMatch?.response.content.text == "GET response")

        let postMatch = matchers.firstMatch(for: postRequest, in: [getEntry, postEntry])
        #expect(postMatch?.response.content.text == "POST response")
    }

    @Test("Filter redacts sensitive headers")
    func filterRedactsHeaders() async throws {
        let entry = makeTestEntry(
            url: "https://api.example.com/secure",
            method: "GET",
            status: 200,
            body: "{}",
            requestHeaders: [
                HAR.Header(name: "Authorization", value: "Bearer secret-token"),
                HAR.Header(name: "Content-Type", value: "application/json"),
            ]
        )

        let filter: Filter = .headers(removing: ["Authorization"])
        let filtered = await filter.apply(to: entry)

        let authHeader = filtered.request.headers.first { $0.name == "Authorization" }
        #expect(authHeader?.value == "[FILTERED]")

        let contentTypeHeader = filtered.request.headers.first { $0.name == "Content-Type" }
        #expect(contentTypeHeader?.value == "application/json")
    }

    @Test("Filter redacts query parameters")
    func filterRedactsQueryParameters() async throws {
        let entry = makeTestEntry(
            url: "https://api.example.com/search?q=test&api_key=secret123",
            method: "GET",
            status: 200,
            body: "{}",
            queryString: [
                HAR.QueryParameter(name: "q", value: "test"),
                HAR.QueryParameter(name: "api_key", value: "secret123"),
            ]
        )

        let filter: Filter = .queryParameters(removing: ["api_key"])
        let filtered = await filter.apply(to: entry)

        let apiKeyParam = filtered.request.queryString.first { $0.name == "api_key" }
        #expect(apiKeyParam?.value == "[FILTERED]")

        let queryParam = filtered.request.queryString.first { $0.name == "q" }
        #expect(queryParam?.value == "test")
    }

    @Test("Replay.RecordMode respects environment")
    func recordingModeRespectsEnvironment() throws {
        let mode = try Replay.RecordMode.fromEnvironment()
        #expect(mode == .none || mode == .once || mode == .rewrite)
    }

    @Test("Archive name without .har suffix works")
    func archiveNameWithoutSuffix() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let archiveName = "test_archive"
        let archiveURL = tempDir.appendingPathComponent("\(archiveName).har")

        // Create a minimal HAR file
        let harContent = """
            {
              "log": {
                "version": "1.2",
                "creator": {
                  "name": "Replay",
                  "version": "1.0"
                },
                "entries": []
              }
            }
            """
        try harContent.write(to: archiveURL, atomically: true, encoding: .utf8)

        let trait = ReplayTrait(archiveName, directory: tempDir.path, rootURL: tempDir)

        // Should not throw since archive exists
        try await trait.provideScope(
            for: Test.current!,
            testCase: nil,
            performing: {}
        )
    }

    @Test("Archive name with .har suffix is normalized")
    func archiveNameWithSuffix() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let archiveName = "test_archive"
        let archiveURL = tempDir.appendingPathComponent("\(archiveName).har")

        // Create a minimal HAR file
        let harContent = """
            {
              "log": {
                "version": "1.2",
                "creator": {
                  "name": "Replay",
                  "version": "1.0"
                },
                "entries": []
              }
            }
            """
        try harContent.write(to: archiveURL, atomically: true, encoding: .utf8)

        // Test with .har suffix - should find the same file
        let trait = ReplayTrait("\(archiveName).har", directory: tempDir.path, rootURL: tempDir)

        // Should not throw since archive exists (normalized name matches)
        try await trait.provideScope(
            for: Test.current!,
            testCase: nil,
            performing: {}
        )
    }

    @Test("Archive name with and without .har suffix resolve to same path")
    func archiveNameNormalization() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let archiveName = "normalization_test"
        let traitWithoutSuffix = ReplayTrait(archiveName, directory: tempDir.path, rootURL: tempDir)
        let traitWithSuffix = ReplayTrait("\(archiveName).har", directory: tempDir.path, rootURL: tempDir)

        // Both should throw archiveMissing with the same path
        do {
            try await traitWithoutSuffix.provideScope(
                for: Test.current!,
                testCase: nil,
                performing: {}
            )
            Issue.record("Expected archiveMissing error")
        } catch let error as ReplayError {
            if case .archiveMissing(let path1, _, _) = error {
                do {
                    try await traitWithSuffix.provideScope(
                        for: Test.current!,
                        testCase: nil,
                        performing: {}
                    )
                    Issue.record("Expected archiveMissing error")
                } catch let error2 as ReplayError {
                    if case .archiveMissing(let path2, _, _) = error2 {
                        // Both should point to the same normalized path
                        #expect(path1 == path2)
                        #expect(path1.lastPathComponent == "\(archiveName).har")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func makeTestEntry(
        url: String,
        method: String,
        status: Int,
        body: String,
        requestHeaders: [HAR.Header] = [],
        queryString: [HAR.QueryParameter] = []
    ) -> HAR.Entry {
        HAR.Entry(
            startedDateTime: Date(),
            time: 100,
            request: HAR.Request(
                method: method,
                url: url,
                httpVersion: "HTTP/1.1",
                headers: requestHeaders,
                queryString: queryString,
                bodySize: 0
            ),
            response: HAR.Response(
                status: status,
                statusText: "OK",
                httpVersion: "HTTP/1.1",
                headers: [HAR.Header(name: "Content-Type", value: "application/json")],
                content: HAR.Content(
                    size: body.utf8.count,
                    mimeType: "application/json",
                    text: body
                ),
                bodySize: body.utf8.count
            ),
            timings: HAR.Timings(send: 0, wait: 100, receive: 0)
        )
    }
}
