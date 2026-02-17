#if canImport(AsyncHTTPClient)

    import AsyncHTTPClient
    import NIOCore

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

#endif  // canImport(AsyncHTTPClient)
