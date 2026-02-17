#if canImport(AsyncHTTPClient)

    import AsyncHTTPClient
    import Foundation
    import NIOCore
    import NIOHTTP1

    #if canImport(FoundationNetworking)
        import FoundationNetworking
    #endif

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
            try await handle(request)
        }

        public func execute(
            _ request: HTTPClientRequest,
            timeout: TimeAmount
        ) async throws -> HTTPClientResponse {
            try await handle(request)
        }

        // MARK: - Private

        private func handle(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
            let urlRequest = try await URLRequest(from: request)
            let disposition = try await store.checkRequest(urlRequest)

            switch disposition {
            case .recorded(_, let data):
                guard
                    let entry = await store.configuration?.matchers.firstMatch(
                        for: urlRequest,
                        in: await store.getAvailableEntries()
                    )
                else {
                    throw ReplayError.invalidResponse
                }
                return HTTPClientResponse(entry: entry, data: data)

            case .error(let error):
                throw error

            case .network(let shouldRecord):
                guard let client = liveClient else {
                    throw ReplayError.notConfigured
                }

                let startTime = Date()
                let response = try await client.execute(request, timeout: .seconds(30))
                let body = try await response.body.collect(upTo: 10 * 1024 * 1024)
                let data = Data(buffer: body)
                let duration = Date().timeIntervalSince(startTime)

                if shouldRecord {
                    var entry = try HAR.Entry(
                        clientRequest: request,
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

                return response
            }
        }
    }

    // MARK: - Conversions

    extension URLRequest {
        /// Creates a `URLRequest` from an `HTTPClientRequest`.
        init(from request: HTTPClientRequest) async throws {
            guard let url = URL(string: request.url) else {
                throw ReplayError.invalidURL(request.url)
            }

            self.init(url: url)
            self.httpMethod = request.method.rawValue

            for header in request.headers {
                self.addValue(header.value, forHTTPHeaderField: header.name)
            }

            if let body = request.body {
                var collected = ByteBuffer()
                for try await var chunk in body {
                    collected.writeBuffer(&chunk)
                }
                self.httpBody = Data(buffer: collected)
            }
        }
    }

    extension HTTPClientResponse {
        /// Creates an `HTTPClientResponse` from a HAR entry's response data.
        init(entry: HAR.Entry, data: Data) {
            var headers = HTTPHeaders()
            for header in entry.response.headers {
                headers.add(name: header.name, value: header.value)
            }

            self.init(
                status: HTTPResponseStatus(statusCode: entry.response.status),
                headers: headers,
                body: data.isEmpty ? .init() : .bytes(ByteBuffer(data: data))
            )
        }
    }

    extension HAR.Entry {
        /// Creates a HAR entry from an `HTTPClientRequest` and response metadata.
        init(
            clientRequest request: HTTPClientRequest,
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

            self.request = HAR.Request(
                method: request.method.rawValue,
                url: request.url,
                httpVersion: "HTTP/1.1",
                headers: harHeaders,
                queryString: queryString,
                headersSize: -1,
                bodySize: 0
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
