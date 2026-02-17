#if canImport(AsyncHTTPClient)

    import AsyncHTTPClient
    import Foundation
    import NIOCore
    import NIOHTTP1

    #if canImport(FoundationNetworking)
        import FoundationNetworking
    #endif

    // MARK: - HTTPClientProtocol

    /// A protocol abstracting over `HTTPClient` for testability.
    ///
    /// Conform to this protocol to enable VCR-style recording and playback
    /// of HTTP traffic without requiring a live network connection.
    ///
    /// `HTTPClient` conforms to this protocol out of the box.
    /// In tests, use ``ReplayHTTPClient`` as a drop-in replacement
    /// to replay responses from HAR archives.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Production code accepts any HTTPClientProtocol
    /// func fetchUser(using client: some HTTPClientProtocol) async throws -> User {
    ///     let request = HTTPClientRequest(url: "https://api.example.com/user")
    ///     let response = try await client.execute(request, timeout: .seconds(30))
    ///     let body = try await response.body.collect(upTo: 1024 * 1024)
    ///     return try JSONDecoder().decode(User.self, from: body)
    /// }
    ///
    /// // In tests, swap in a ReplayHTTPClient:
    /// let client = try await ReplayHTTPClient(
    ///     configuration: PlaybackConfiguration(source: .file(archiveURL))
    /// )
    /// let user = try await fetchUser(using: client)
    /// ```
    public protocol HTTPClientProtocol: Sendable {
        /// Execute an HTTP request with a deadline.
        ///
        /// - Parameters:
        ///   - request: The HTTP request to execute.
        ///   - deadline: Point in time by which the request must complete.
        /// - Returns: The HTTP response.
        func execute(
            _ request: HTTPClientRequest,
            deadline: NIODeadline
        ) async throws -> HTTPClientResponse

        /// Execute an HTTP request with a timeout.
        ///
        /// - Parameters:
        ///   - request: The HTTP request to execute.
        ///   - timeout: Maximum time the request may take.
        /// - Returns: The HTTP response.
        func execute(
            _ request: HTTPClientRequest,
            timeout: TimeAmount
        ) async throws -> HTTPClientResponse
    }

    extension HTTPClient: HTTPClientProtocol {
        public func execute(
            _ request: HTTPClientRequest,
            deadline: NIODeadline
        ) async throws -> HTTPClientResponse {
            try await execute(request, deadline: deadline, logger: nil)
        }

        public func execute(
            _ request: HTTPClientRequest,
            timeout: TimeAmount
        ) async throws -> HTTPClientResponse {
            try await execute(request, timeout: timeout, logger: nil)
        }
    }

    // MARK: - ReplayHTTPClient

    /// An ``HTTPClientProtocol`` implementation that replays HTTP responses
    /// from recorded HAR archives or in-memory stubs.
    ///
    /// `ReplayHTTPClient` delegates to Replay's ``PlaybackStore`` for request matching
    /// and response lookup. In `.passthrough` or `.live` playback mode,
    /// unmatched requests are forwarded to a real `HTTPClient`.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let client = try await ReplayHTTPClient(
    ///     configuration: PlaybackConfiguration(
    ///         source: .file(archiveURL),
    ///         playbackMode: .strict
    ///     )
    /// )
    ///
    /// let request = HTTPClientRequest(url: "https://api.example.com/data")
    /// let response = try await client.execute(request, timeout: .seconds(30))
    /// ```
    public final class ReplayHTTPClient: HTTPClientProtocol {
        private let store: PlaybackStore
        private let liveClient: HTTPClient?

        /// Creates a replay client with the given playback configuration.
        ///
        /// - Parameters:
        ///   - configuration: The playback configuration controlling source, mode, matchers, and filters.
        ///   - liveClient: An optional `HTTPClient` used for network requests in `.passthrough` or `.live` mode.
        public init(
            configuration: PlaybackConfiguration,
            liveClient: HTTPClient? = nil
        ) async throws {
            self.store = PlaybackStore()
            self.liveClient = liveClient
            try await store.configure(configuration)
        }

        /// Creates a replay client from in-memory stubs.
        ///
        /// - Parameters:
        ///   - stubs: The stubs to use for playback.
        ///   - matchers: Matchers used to match incoming requests to stubs.
        public init(
            stubs: [Stub],
            matchers: [Matcher] = .default
        ) async throws {
            self.store = PlaybackStore()
            self.liveClient = nil
            try await store.configure(
                PlaybackConfiguration(
                    source: .stubs(stubs),
                    playbackMode: .strict,
                    recordMode: .none,
                    matchers: matchers
                )
            )
        }

        public func execute(
            _ request: HTTPClientRequest,
            deadline: NIODeadline
        ) async throws -> HTTPClientResponse {
            try await handle(request, deadline: deadline)
        }

        public func execute(
            _ request: HTTPClientRequest,
            timeout: TimeAmount
        ) async throws -> HTTPClientResponse {
            try await handle(request, deadline: .now() + timeout)
        }

        // MARK: - Private

        private func handle(
            _ request: HTTPClientRequest,
            deadline: NIODeadline
        ) async throws -> HTTPClientResponse {
            guard URL(string: request.url) != nil else {
                throw ReplayError.invalidURL(request.url)
            }

            // Materialize the body once so it can be used for both matching and forwarding.
            var materializedRequest = request
            var bodyData: Data?
            if let body = request.body {
                var collected = ByteBuffer()
                for try await var chunk in body {
                    collected.writeBuffer(&chunk)
                }
                bodyData = Data(buffer: collected)
                materializedRequest.body = .bytes(collected)
            }

            let urlRequest = URLRequest(from: materializedRequest, bodyData: bodyData)
            let disposition = try await store.checkRequest(urlRequest)

            switch disposition {
            case .recorded(let response, let data):
                return HTTPClientResponse(response: response, data: data)

            case .error(let error):
                throw error

            case .network(let shouldRecord):
                guard let client = liveClient else {
                    throw ReplayError.notConfigured
                }

                let startTime = Date()
                let response = try await client.execute(
                    materializedRequest, deadline: deadline)
                let body = try await response.body.collect(upTo: 10 * 1024 * 1024)
                let data = Data(buffer: body)
                let duration = Date().timeIntervalSince(startTime)

                if shouldRecord {
                    var entry = try HAR.Entry(
                        clientRequest: materializedRequest,
                        bodyData: bodyData,
                        status: Int(response.status.code),
                        responseHeaders: response.headers,
                        data: data,
                        startTime: startTime,
                        duration: duration
                    )

                    if let filters = await store.configuration?.filters {
                        for filter in filters {
                            entry = await filter.apply(to: entry)
                        }
                    }

                    try await store.recordEntry(entry)
                }

                return HTTPClientResponse(
                    status: response.status,
                    headers: response.headers,
                    body: .bytes(ByteBuffer(data: data))
                )
            }
        }
    }

    // MARK: - Conversions

    extension URLRequest {
        /// Creates a `URLRequest` from an `HTTPClientRequest` with pre-materialized body data.
        init(from request: HTTPClientRequest, bodyData: Data?) {
            // Force-unwrap is safe: handle(_:) validated the URL before calling this.
            self.init(url: URL(string: request.url)!)
            self.httpMethod = request.method.rawValue

            for header in request.headers {
                self.addValue(header.value, forHTTPHeaderField: header.name)
            }

            self.httpBody = bodyData
        }
    }

    extension HTTPClientResponse {
        /// Creates an `HTTPClientResponse` from an `HTTPURLResponse` and body data.
        init(response: HTTPURLResponse, data: Data) {
            var headers = HTTPHeaders()
            for (key, value) in response.allHeaderFields {
                headers.add(name: String(describing: key), value: String(describing: value))
            }

            self.init(
                status: HTTPResponseStatus(statusCode: response.statusCode),
                headers: headers,
                body: data.isEmpty ? .init() : .bytes(ByteBuffer(data: data))
            )
        }
    }

    extension HAR.Entry {
        /// Creates a HAR entry from an `HTTPClientRequest` and response metadata.
        ///
        /// - Parameters:
        ///   - request: The original HTTP client request.
        ///   - bodyData: Pre-materialized request body data, if any.
        ///   - status: The HTTP response status code.
        ///   - responseHeaders: The HTTP response headers.
        ///   - data: The response body data.
        ///   - startTime: When the request started.
        ///   - duration: How long the request took.
        init(
            clientRequest request: HTTPClientRequest,
            bodyData: Data? = nil,
            status: Int,
            responseHeaders: HTTPHeaders,
            data: Data,
            startTime: Date,
            duration: TimeInterval
        ) throws {
            guard URL(string: request.url) != nil else {
                throw ReplayError.invalidURL(request.url)
            }

            self.startedDateTime = startTime
            self.time = Int(duration * 1000)

            // Build HAR request
            var harHeaders: [HAR.Header] = request.headers.map {
                HAR.Header(name: $0.name, value: $0.value)
            }
            harHeaders.sort { $0.name < $1.name }

            let components = URLComponents(string: request.url)
            let queryString: [HAR.QueryParameter] =
                components?.queryItems?.map { item in
                    HAR.QueryParameter(name: item.name, value: item.value ?? "")
                } ?? []

            var postData: HAR.PostData?
            if let bodyData, !bodyData.isEmpty {
                let contentType =
                    request.headers.first(name: "Content-Type") ?? "application/octet-stream"
                let utf8Text = String(data: bodyData, encoding: .utf8)
                postData = HAR.PostData(
                    mimeType: contentType,
                    text: utf8Text ?? bodyData.base64EncodedString()
                )
            }

            self.request = HAR.Request(
                method: request.method.rawValue,
                url: request.url,
                httpVersion: "HTTP/1.1",
                headers: harHeaders,
                queryString: queryString,
                postData: postData,
                headersSize: -1,
                bodySize: bodyData?.count ?? 0
            )

            // Build HAR response
            var harResponseHeaders: [HAR.Header] = responseHeaders.map {
                HAR.Header(name: $0.name, value: $0.value)
            }
            harResponseHeaders.sort { $0.name < $1.name }

            let mimeType = responseHeaders.first(name: "Content-Type") ?? "application/octet-stream"
            let utf8Text = String(data: data, encoding: .utf8)
            let encoding = utf8Text == nil && !data.isEmpty ? "base64" : nil

            self.response = HAR.Response(
                status: status,
                statusText: HTTPResponseStatus(statusCode: status).reasonPhrase,
                httpVersion: "HTTP/1.1",
                headers: harResponseHeaders,
                content: HAR.Content(
                    size: data.count,
                    mimeType: mimeType,
                    text: utf8Text ?? data.base64EncodedString(),
                    encoding: encoding
                ),
                bodySize: data.count
            )

            self.cache = nil
            self.timings = HAR.Timings(
                send: 0,
                wait: Int(duration * 1000),
                receive: 0
            )
        }
    }

#endif  // canImport(AsyncHTTPClient)
