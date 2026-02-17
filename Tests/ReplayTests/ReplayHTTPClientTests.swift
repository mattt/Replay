#if canImport(AsyncHTTPClient)

    import AsyncHTTPClient
    import Foundation
    #if canImport(FoundationNetworking)
        import FoundationNetworking
    #endif
    import NIOCore
    import NIOHTTP1
    import Testing

    @testable import Replay

    @Suite("ReplayHTTPClient Tests")
    struct ReplayHTTPClientTests {

        // MARK: - HTTPClientProtocol Conformance

        @Test("HTTPClient conforms to HTTPClientProtocol")
        func httpClientConformance() {
            // Compile-time check: HTTPClient conforms to HTTPClientProtocol
            func acceptsProtocol(_: some HTTPClientProtocol) {}
            let client = HTTPClient()
            acceptsProtocol(client)
            try? client.syncShutdown()
        }

        @Test("ReplayHTTPClient conforms to HTTPClientProtocol")
        func replayClientConformance() async throws {
            let client = try await ReplayHTTPClient(
                stubs: [
                    Stub(.get, "https://example.com", status: 200, body: "OK")
                ]
            )

            func acceptsProtocol(_: some HTTPClientProtocol) {}
            acceptsProtocol(client)
        }

        // MARK: - Stub-Based Playback

        @Test("replays GET request from stubs")
        func replaysGetFromStubs() async throws {
            let client = try await ReplayHTTPClient(
                stubs: [
                    Stub(
                        .get, "https://api.example.com/data", status: 200,
                        headers: ["Content-Type": "application/json"], body: "{\"ok\":true}")
                ]
            )

            var request = HTTPClientRequest(url: "https://api.example.com/data")
            request.method = .GET

            let response = try await client.execute(request, timeout: .seconds(5))

            #expect(response.status == .ok)
            let body = try await response.body.collect(upTo: 1024)
            let text = String(buffer: body)
            #expect(text == "{\"ok\":true}")
        }

        @Test("replays POST request from stubs")
        func replaysPostFromStubs() async throws {
            let client = try await ReplayHTTPClient(
                stubs: [
                    Stub(.post, "https://api.example.com/users", status: 201, body: "Created")
                ]
            )

            var request = HTTPClientRequest(url: "https://api.example.com/users")
            request.method = .POST

            let response = try await client.execute(request, timeout: .seconds(5))

            #expect(response.status == .created)
        }

        @Test("replays multiple stubs matched by URL")
        func replaysMultipleStubs() async throws {
            let client = try await ReplayHTTPClient(
                stubs: [
                    Stub(.get, "https://api.example.com/first", status: 200, body: "First"),
                    Stub(.get, "https://api.example.com/second", status: 200, body: "Second"),
                ]
            )

            let response1 = try await client.execute(
                HTTPClientRequest(url: "https://api.example.com/first"),
                timeout: .seconds(5)
            )
            let body1 = try await response1.body.collect(upTo: 1024)

            let response2 = try await client.execute(
                HTTPClientRequest(url: "https://api.example.com/second"),
                timeout: .seconds(5)
            )
            let body2 = try await response2.body.collect(upTo: 1024)

            #expect(String(buffer: body1) == "First")
            #expect(String(buffer: body2) == "Second")
        }

        // MARK: - Entry-Based Playback

        @Test("replays from HAR entries")
        func replaysFromEntries() async throws {
            let entry = HAR.Entry(
                startedDateTime: Date(),
                time: 100,
                request: HAR.Request(
                    method: "GET",
                    url: "https://api.example.com/status",
                    httpVersion: "HTTP/1.1",
                    headers: [],
                    bodySize: 0
                ),
                response: HAR.Response(
                    status: 204,
                    statusText: "No Content",
                    httpVersion: "HTTP/1.1",
                    headers: [],
                    content: HAR.Content(size: 0, mimeType: "text/plain", text: ""),
                    bodySize: 0
                ),
                timings: HAR.Timings(send: 0, wait: 100, receive: 0)
            )

            let client = try await ReplayHTTPClient(
                configuration: PlaybackConfiguration(source: .entries([entry]))
            )

            let response = try await client.execute(
                HTTPClientRequest(url: "https://api.example.com/status"),
                timeout: .seconds(5)
            )

            #expect(response.status == .noContent)
        }

        // MARK: - Response Headers

        @Test("preserves response headers from stubs")
        func preservesResponseHeaders() async throws {
            let client = try await ReplayHTTPClient(
                stubs: [
                    Stub(
                        .get,
                        "https://api.example.com/data",
                        status: 200,
                        headers: [
                            "Content-Type": "application/json",
                            "X-Custom": "test-value",
                        ],
                        body: "{}"
                    )
                ]
            )

            let response = try await client.execute(
                HTTPClientRequest(url: "https://api.example.com/data"),
                timeout: .seconds(5)
            )

            #expect(response.headers.first(name: "X-Custom") == "test-value")
        }

        // MARK: - Strict Mode

        @Test("strict mode throws for unmatched requests")
        func strictModeThrows() async throws {
            let client = try await ReplayHTTPClient(
                stubs: [
                    Stub(.get, "https://expected.com", status: 200, body: "OK")
                ]
            )

            await #expect(throws: ReplayError.self) {
                _ = try await client.execute(
                    HTTPClientRequest(url: "https://unexpected.com"),
                    timeout: .seconds(5)
                )
            }
        }

        // MARK: - Deadline-Based Execute

        @Test("execute with deadline works")
        func executeWithDeadline() async throws {
            let client = try await ReplayHTTPClient(
                stubs: [
                    Stub(.get, "https://api.example.com/data", status: 200, body: "OK")
                ]
            )

            let response = try await client.execute(
                HTTPClientRequest(url: "https://api.example.com/data"),
                deadline: .now() + .seconds(5)
            )

            #expect(response.status == .ok)
        }

        // MARK: - Empty Body

        @Test("handles empty response body")
        func handlesEmptyBody() async throws {
            let client = try await ReplayHTTPClient(
                stubs: [
                    Stub(.delete, "https://api.example.com/item/1", status: 204)
                ]
            )

            var request = HTTPClientRequest(url: "https://api.example.com/item/1")
            request.method = .DELETE

            let response = try await client.execute(request, timeout: .seconds(5))

            #expect(response.status == .noContent)
            let body = try await response.body.collect(upTo: 1024)
            #expect(body.readableBytes == 0)
        }

        // MARK: - Conversion Tests

        @Suite("Conversion Tests")
        struct ConversionTests {
            @Test("URLRequest from HTTPClientRequest preserves method and URL")
            func urlRequestFromHTTPClientRequest() {
                var request = HTTPClientRequest(url: "https://api.example.com/users?page=1")
                request.method = .POST
                request.headers.add(name: "Content-Type", value: "application/json")

                let urlRequest = URLRequest(from: request, bodyData: nil)

                #expect(urlRequest.httpMethod == "POST")
                #expect(urlRequest.url?.absoluteString == "https://api.example.com/users?page=1")
                #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
            }

            @Test("URLRequest from HTTPClientRequest preserves body")
            func urlRequestPreservesBody() {
                var request = HTTPClientRequest(url: "https://api.example.com/data")
                request.method = .POST

                let bodyData = "hello".data(using: .utf8)
                let urlRequest = URLRequest(from: request, bodyData: bodyData)

                #expect(urlRequest.httpBody == bodyData)
            }

            @Test("HTTPClientResponse from HTTPURLResponse preserves status and headers")
            func httpClientResponseFromHTTPURLResponse() {
                let httpResponse = HTTPURLResponse(
                    url: URL(string: "https://example.com")!,
                    statusCode: 201,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["X-Request-Id": "abc123"]
                )!

                let response = HTTPClientResponse(
                    response: httpResponse, data: "done".data(using: .utf8)!)

                #expect(response.status == .created)
                #expect(response.headers.first(name: "X-Request-Id") == "abc123")
            }

            @Test("HAR.Entry from HTTPClientRequest captures method and URL")
            func harEntryFromClientRequest() throws {
                var request = HTTPClientRequest(url: "https://api.example.com/users?page=2")
                request.method = .POST
                request.headers.add(name: "Authorization", value: "Bearer token")

                let entry = try HAR.Entry(
                    clientRequest: request,
                    status: 200,
                    responseHeaders: HTTPHeaders([("Content-Type", "application/json")]),
                    data: "{\"ok\":true}".data(using: .utf8)!,
                    startTime: Date(),
                    duration: 0.5
                )

                #expect(entry.request.method == "POST")
                #expect(entry.request.url == "https://api.example.com/users?page=2")
                #expect(entry.response.status == 200)
                #expect(entry.response.content.text == "{\"ok\":true}")
                #expect(entry.time == 500)
            }
        }
    }

#endif  // canImport(AsyncHTTPClient)
