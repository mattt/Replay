import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Namespace for HAR (HTTP Archive) types and utilities.
///
/// The HTTP Archive format is used to export HTTP tracing data and is based on JSON.
/// HAR files are required to be saved in UTF-8 encoding.
///
/// - SeeAlso: [HAR 1.2 Specification](http://www.softwareishard.com/blog/har-12-spec)
public enum HAR {
    /// Root HAR log object (HAR 1.2 `log` object).
    ///
    /// This object represents the root of exported data.
    public struct Log: Hashable, Codable, Sendable {
        /// Version number of the format.
        ///
        /// If empty, string "1.1" is assumed by default.
        public var version: String

        /// Name and version info of the log creator application.
        public var creator: Creator

        /// Name and version info of the used browser.
        ///
        /// May be omitted if not applicable.
        public var browser: Browser?

        /// List of all exported (tracked) pages.
        ///
        /// Leave out this field if the application does not support grouping by pages.
        public var pages: [Page]?

        /// List of all exported (tracked) requests.
        ///
        /// Sorting entries by `startedDateTime` (starting from the oldest) is the preferred way
        /// to export data since it can make importing faster.
        public var entries: [Entry]

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            version: String,
            creator: Creator,
            browser: Browser? = nil,
            pages: [Page]? = nil,
            entries: [Entry] = [],
            comment: String? = nil
        ) {
            self.version = version
            self.creator = creator
            self.browser = browser
            self.pages = pages
            self.entries = entries
            self.comment = comment
        }
    }

    /// Creator or browser information.
    ///
    /// Used to identify the application that created the HAR log.
    /// The `Creator` and `Browser` types share the same structure.
    public struct Creator: Hashable, Codable, Sendable {
        /// Name of the application/browser used to export the log.
        public var name: String

        /// Version of the application/browser used to export the log.
        public var version: String

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            name: String,
            version: String,
            comment: String? = nil
        ) {
            self.name = name
            self.version = version
            self.comment = comment
        }
    }

    /// Browser information.
    ///
    /// Shares the same structure as `Creator`.
    public typealias Browser = Creator

    // MARK: - Page

    /// Represents an exported web page.
    ///
    /// There is one `Page` object for every exported web page.
    /// In cases when an HTTP trace tool isn't able to group requests by a page,
    /// the pages array is empty and individual requests don't have a parent page.
    public struct Page: Hashable, Codable, Sendable {
        /// Date and time stamp for the beginning of the page load.
        public var startedDateTime: Date

        /// Unique identifier of a page within the log.
        ///
        /// Entries use this to refer to the parent page.
        public var id: String

        /// Page title.
        public var title: String

        /// Detailed timing info about page load.
        public var pageTimings: PageTimings

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            startedDateTime: Date,
            id: String,
            title: String,
            pageTimings: PageTimings,
            comment: String? = nil
        ) {
            self.startedDateTime = startedDateTime
            self.id = id
            self.title = title
            self.pageTimings = pageTimings
            self.comment = comment
        }

        /// Timings for various events (states) fired during the page load.
        ///
        /// All times are specified in milliseconds.
        /// If a time info is not available,
        /// the appropriate field is set to -1.
        public struct PageTimings: Hashable, Codable, Sendable {
            /// Content of the page loaded.
            ///
            /// Number of milliseconds since page load started (`page.startedDateTime`).
            /// Use -1 if the timing does not apply to the current request.
            /// Depending on the browser, represents `DOMContentLoad` event or
            /// `document.readyState == interactive`.
            public var onContentLoad: Int?

            /// Page is loaded (onLoad event fired).
            ///
            /// Number of milliseconds since page load started (`page.startedDateTime`).
            /// Use -1 if the timing does not apply to the current request.
            public var onLoad: Int?

            /// A comment provided by the user or the application.
            ///
            public var comment: String?

            public init(
                onContentLoad: Int? = nil,
                onLoad: Int? = nil,
                comment: String? = nil
            ) {
                self.onContentLoad = onContentLoad
                self.onLoad = onLoad
                self.comment = comment
            }
        }
    }

    // MARK: - Entry

    /// Represents an individual HTTP request/response pair.
    ///
    /// There is one `Entry` object for every HTTP request.
    public struct Entry: Hashable, Codable, Sendable {
        /// Date and time stamp of the request start.
        ///
        /// Format: ISO 8601 (YYYY-MM-DDThh:mm:ss.sTZD).
        public var startedDateTime: Date

        /// Total elapsed time of the request in milliseconds.
        ///
        /// This is the sum of all timings available in the timings object
        /// (i.e. not including -1 values).
        public var time: Int

        /// Detailed info about the request.
        public var request: Request

        /// Detailed info about the response.
        public var response: Response

        /// Info about cache usage.
        public var cache: Cache?

        /// Detailed timing info about request/response round trip.
        public var timings: Timings

        /// IP address of the server that was connected (result of DNS resolution).
        public var serverIPAddress: String?

        /// Unique ID of the parent TCP/IP connection.
        ///
        /// Can be the client or server port number. Note that a port number doesn't have to be
        /// a unique identifier in cases where the port is shared for more connections.
        /// If the port isn't available for the application, any other unique connection ID
        /// can be used instead (e.g. connection index).
        public var connection: String?

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            startedDateTime: Date,
            time: Int,
            request: Request,
            response: Response,
            cache: Cache? = nil,
            timings: Timings,
            serverIPAddress: String? = nil,
            connection: String? = nil,
            comment: String? = nil
        ) {
            self.startedDateTime = startedDateTime
            self.time = time
            self.request = request
            self.response = response
            self.cache = cache
            self.timings = timings
            self.serverIPAddress = serverIPAddress
            self.connection = connection
            self.comment = comment
        }
    }

    // MARK: - Request / Response

    /// Detailed info about an HTTP request.
    public struct Request: Hashable, Codable, Sendable {
        /// Request method (GET, POST, etc.).
        public var method: String

        /// Absolute URL of the request (fragments are not included).
        public var url: String

        /// Request HTTP version.
        public var httpVersion: String

        /// List of cookie objects.
        public var cookies: [Cookie]

        /// List of header objects.
        public var headers: [Header]

        /// List of query parameter objects.
        public var queryString: [QueryParameter]

        /// Posted data info.
        public var postData: PostData?

        /// Total number of bytes from the start of the HTTP request message
        /// until (and including) the double CRLF before the body.
        ///
        /// Set to -1 if the info is not available.
        public var headersSize: Int

        /// Size of the request body (POST data payload) in bytes.
        ///
        /// Set to -1 if the info is not available.
        public var bodySize: Int

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            method: String,
            url: String,
            httpVersion: String,
            cookies: [Cookie] = [],
            headers: [Header],
            queryString: [QueryParameter] = [],
            postData: PostData? = nil,
            headersSize: Int = -1,
            bodySize: Int,
            comment: String? = nil
        ) {
            self.method = method
            self.url = url
            self.httpVersion = httpVersion
            self.cookies = cookies
            self.headers = headers
            self.queryString = queryString
            self.postData = postData
            self.headersSize = headersSize
            self.bodySize = bodySize
            self.comment = comment
        }
    }

    /// Detailed info about an HTTP response.
    public struct Response: Hashable, Codable, Sendable {
        /// Response status code.
        public var status: Int

        /// Response status description.
        public var statusText: String

        /// Response HTTP version.
        public var httpVersion: String

        /// List of cookie objects.
        public var cookies: [Cookie]

        /// List of header objects.
        public var headers: [Header]

        /// Details about the response body.
        public var content: Content

        /// Redirection target URL from the Location response header.
        public var redirectURL: String

        /// Total number of bytes from the start of the HTTP response message
        /// until (and including) the double CRLF before the body.
        ///
        /// Set to -1 if the info is not available.
        /// The size of received response-headers is computed only from headers
        /// that are really received from the server. Additional headers appended
        /// by the browser are not included in this number.
        public var headersSize: Int

        /// Size of the received response body in bytes.
        ///
        /// Set to zero in case of responses coming from the cache (304).
        /// Set to -1 if the info is not available.
        public var bodySize: Int

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            status: Int,
            statusText: String,
            httpVersion: String,
            cookies: [Cookie] = [],
            headers: [Header],
            content: Content,
            redirectURL: String = "",
            headersSize: Int = -1,
            bodySize: Int,
            comment: String? = nil
        ) {
            self.status = status
            self.statusText = statusText
            self.httpVersion = httpVersion
            self.cookies = cookies
            self.headers = headers
            self.content = content
            self.redirectURL = redirectURL
            self.headersSize = headersSize
            self.bodySize = bodySize
            self.comment = comment
        }
    }

    /// Details about the response body content.
    public struct Content: Hashable, Codable, Sendable {
        /// Length of the returned content in bytes.
        ///
        /// Should be equal to `response.bodySize` if there is no compression,
        /// and bigger when the content has been compressed.
        public var size: Int

        /// Number of bytes saved due to compression.
        ///
        /// Leave out this field if the information is not available.
        public var compression: Int?

        /// MIME type of the response text (value of the Content-Type response header).
        ///
        /// The charset attribute of the MIME type is included (if available).
        public var mimeType: String

        /// Response body sent from the server or loaded from the browser cache.
        ///
        /// This field is populated with textual content only. The text field is either
        /// HTTP decoded text or an encoded (e.g. "base64") representation of the response body.
        /// Leave out this field if the information is not available.
        ///
        /// Before setting the text field, the HTTP response is decoded (decompressed & unchunked),
        /// then trans-coded from its original character set into UTF-8.
        public var text: String?

        /// Encoding used for the response text field (e.g. "base64").
        ///
        /// Leave out this field if the text field is HTTP decoded
        /// (decompressed & unchunked), then trans-coded from its original
        /// character set into UTF-8.
        ///
        /// Useful for including binary responses (e.g. images) into the HAR file.
        public var encoding: String?

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            size: Int,
            compression: Int? = nil,
            mimeType: String,
            text: String? = nil,
            encoding: String? = nil,
            comment: String? = nil
        ) {
            self.size = size
            self.compression = compression
            self.mimeType = mimeType
            self.text = text
            self.encoding = encoding
            self.comment = comment
        }
    }

    /// HTTP header name/value pair.
    public struct Header: Hashable, Codable, Sendable {
        /// Header name.
        public var name: String

        /// Header value.
        public var value: String

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            name: String,
            value: String,
            comment: String? = nil
        ) {
            self.name = name
            self.value = value
            self.comment = comment
        }
    }

    /// HTTP cookie.
    public struct Cookie: Hashable, Codable, Sendable {
        /// The name of the cookie.
        public var name: String

        /// The cookie value.
        public var value: String

        /// The path pertaining to the cookie.
        public var path: String?

        /// The host of the cookie.
        public var domain: String?

        /// Cookie expiration time.
        public var expires: Date?

        /// Whether the cookie is HTTP only.
        ///
        /// Set to `true` if the cookie is HTTP only, `false` otherwise.
        public var httpOnly: Bool?

        /// Whether the cookie was transmitted over SSL.
        ///
        /// `true` if the cookie was transmitted over SSL, `false` otherwise.
        public var secure: Bool?

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            name: String,
            value: String,
            path: String? = nil,
            domain: String? = nil,
            expires: Date? = nil,
            httpOnly: Bool? = nil,
            secure: Bool? = nil,
            comment: String? = nil
        ) {
            self.name = name
            self.value = value
            self.path = path
            self.domain = domain
            self.expires = expires
            self.httpOnly = httpOnly
            self.secure = secure
            self.comment = comment
        }
    }

    /// Query string parameter name/value pair.
    ///
    /// HAR format expects NVP (name-value pairs) formatting of the query string.
    public struct QueryParameter: Hashable, Codable, Sendable {
        /// Parameter name.
        public var name: String

        /// Parameter value.
        public var value: String

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            name: String,
            value: String,
            comment: String? = nil
        ) {
            self.name = name
            self.value = value
            self.comment = comment
        }
    }

    /// Posted data (embedded in request object).
    public struct PostData: Hashable, Codable, Sendable {
        /// MIME type of posted data.
        public var mimeType: String

        /// List of posted parameters (in case of URL encoded parameters).
        public var params: [Param]?

        /// Plain text posted data.
        public var text: String?

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            mimeType: String,
            params: [Param]? = nil,
            text: String? = nil,
            comment: String? = nil
        ) {
            self.mimeType = mimeType
            self.params = params
            self.text = text
            self.comment = comment
        }

        /// Posted parameter.
        public struct Param: Hashable, Codable, Sendable {
            /// Name of the posted parameter.
            public var name: String

            /// Value of the posted parameter, or content of a posted file.
            public var value: String?

            /// Name of a posted file.
            public var fileName: String?

            /// Content type of a posted file.
            public var contentType: String?

            /// A comment provided by the user or the application.
            public var comment: String?

            public init(
                name: String,
                value: String? = nil,
                fileName: String? = nil,
                contentType: String? = nil,
                comment: String? = nil
            ) {
                self.name = name
                self.value = value
                self.fileName = fileName
                self.contentType = contentType
                self.comment = comment
            }
        }
    }

    /// Detailed timing info about request/response round trip.
    ///
    /// All times are specified in milliseconds. Use -1 for timing phases not applicable
    /// to the current request.
    public struct Timings: Hashable, Codable, Sendable {
        /// Time spent in a queue waiting for a network connection.
        ///
        /// Use -1 if the timing does not apply to the current request.
        /// Optional.
        public var blocked: Int?

        /// DNS resolution time. The time required to resolve a host name.
        ///
        /// Use -1 if the timing does not apply to the current request.
        public var dns: Int?

        /// Time required to create TCP connection.
        ///
        /// Use -1 if the timing does not apply to the current request.
        public var connect: Int?

        /// Time required to send HTTP request to the server.
        public var send: Int

        /// Waiting for a response from the server.
        public var wait: Int

        /// Time required to read entire response from the server (or cache).
        public var receive: Int

        /// Time required for SSL/TLS negotiation.
        ///
        /// If this field is defined, the time is also included in the `connect` field
        /// (to ensure backward compatibility with HAR 1.1).
        /// Use -1 if the timing does not apply to the current request.
        public var ssl: Int?

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            blocked: Int? = nil,
            dns: Int? = nil,
            connect: Int? = nil,
            send: Int,
            wait: Int,
            receive: Int,
            ssl: Int? = nil,
            comment: String? = nil
        ) {
            self.blocked = blocked
            self.dns = dns
            self.connect = connect
            self.send = send
            self.wait = wait
            self.receive = receive
            self.ssl = ssl
            self.comment = comment
        }
    }

    /// Info about a request coming from browser cache.
    public struct Cache: Hashable, Codable, Sendable {
        /// State of a cache entry before the request.
        ///
        /// Leave out this field if the information is not available.
        public var beforeRequest: CacheEntry?

        /// State of a cache entry after the request.
        ///
        /// Leave out this field if the information is not available.
        public var afterRequest: CacheEntry?

        /// A comment provided by the user or the application.
        public var comment: String?

        public init(
            beforeRequest: CacheEntry? = nil,
            afterRequest: CacheEntry? = nil,
            comment: String? = nil
        ) {
            self.beforeRequest = beforeRequest
            self.afterRequest = afterRequest
            self.comment = comment
        }

        /// State of a cache entry.
        public struct CacheEntry: Hashable, Codable, Sendable {
            /// Expiration time of the cache entry.
            public var expires: Date?

            /// The last time the cache entry was opened.
            public var lastAccess: Date

            /// ETag of the cache entry.
            public var eTag: String

            /// The number of times the cache entry has been opened.
            public var hitCount: Int

            /// A comment provided by the user or the application.
            public var comment: String?

            public init(
                expires: Date? = nil,
                lastAccess: Date,
                eTag: String,
                hitCount: Int,
                comment: String? = nil
            ) {
                self.expires = expires
                self.lastAccess = lastAccess
                self.eTag = eTag
                self.hitCount = hitCount
                self.comment = comment
            }
        }
    }
}

// MARK: - HAR Reading / Writing

extension HAR {
    /// Load HAR from file, returning the root `HAR.Log` structure.
    public static func load(from url: URL) throws -> Log {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(Document.self, from: data)
        return document.log
    }

    /// Save HAR log to file.
    public static func save(_ log: Log, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Document(log: log))
        try data.write(to: url)
    }

    /// Create an empty HAR log.
    public static func create(creator: String = "Replay/1.0") -> Log {
        Log(
            version: "1.2",
            creator: Creator(name: creator, version: "1.0"),
            browser: nil,
            pages: nil,
            entries: [],
            comment: nil
        )
    }

    /// Internal document wrapper matching the HAR 1.2 root object.
    private struct Document: Codable {
        var log: Log
    }
}

// MARK: - URLRequest / URLResponse Conversion

extension HAR.Entry {
    /// Create an entry from a `URLRequest` and `HTTPURLResponse`.
    public init(
        request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        startTime: Date,
        duration: TimeInterval
    ) throws {
        self.startedDateTime = startTime
        self.time = Int(duration * 1000)  // milliseconds

        self.request = try HAR.Request(from: request)
        self.response = try HAR.Response(from: response, data: data)

        self.cache = nil
        self.timings = HAR.Timings(
            send: 0,
            wait: Int(duration * 1000),
            receive: 0
        )
        self.serverIPAddress = nil
        self.connection = nil
        self.comment = nil
    }
}

extension HAR.Request {
    public init(from urlRequest: URLRequest) throws {
        guard let url = urlRequest.url else {
            throw ReplayError.invalidRequest("Missing URL")
        }

        self.method = urlRequest.httpMethod ?? "GET"
        self.url = url.absoluteString
        self.httpVersion = "HTTP/1.1"

        // Headers
        self.headers = (urlRequest.allHTTPHeaderFields ?? [:]).map { key, value in
            HAR.Header(name: key, value: value)
        }

        // Query string
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        self.queryString =
            components?.queryItems?.map { item in
                HAR.QueryParameter(name: item.name, value: item.value ?? "")
            } ?? []

        // Body
        if let body = urlRequest.httpBody {
            let contentType =
                urlRequest.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            let utf8Text = String(data: body, encoding: .utf8)
            let text = utf8Text ?? body.base64EncodedString()

            self.postData = HAR.PostData(
                mimeType: contentType,
                params: nil,
                text: text
            )
            self.bodySize = body.count
        } else {
            self.postData = nil
            self.bodySize = 0
        }

        if let cookieHeader = urlRequest.value(forHTTPHeaderField: "Cookie") {
            self.cookies =
                cookieHeader
                .split(separator: ";")
                .compactMap { pair in
                    let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    return HAR.Cookie(name: String(parts[0]), value: String(parts[1]))
                }
        } else {
            self.cookies = []
        }
        self.headersSize = -1
        self.comment = nil
    }
}

extension HAR.Response {
    public init(from httpResponse: HTTPURLResponse, data: Data) throws {
        self.status = httpResponse.statusCode
        self.statusText = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
        self.httpVersion = "HTTP/1.1"

        self.headers = httpResponse.allHeaderFields.map { key, value in
            HAR.Header(name: String(describing: key), value: String(describing: value))
        }

        let mimeType = httpResponse.mimeType ?? "application/octet-stream"
        let utf8Text = String(data: data, encoding: .utf8)
        let encoding = utf8Text == nil && !data.isEmpty ? "base64" : nil

        self.content = HAR.Content(
            size: data.count,
            compression: nil,
            mimeType: mimeType,
            text: utf8Text ?? data.base64EncodedString(),
            encoding: encoding
        )

        if let url = httpResponse.url {
            var headerFields: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                headerFields[String(describing: key)] = String(describing: value)
            }

            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            self.cookies = cookies.map { cookie in
                HAR.Cookie(
                    name: cookie.name,
                    value: cookie.value,
                    path: cookie.path,
                    domain: cookie.domain,
                    expires: cookie.expiresDate,
                    httpOnly: cookie.isHTTPOnly,
                    secure: cookie.isSecure,
                    comment: cookie.comment
                )
            }
        } else {
            self.cookies = []
        }
        self.redirectURL = ""
        self.headersSize = -1
        self.bodySize = data.count
        self.comment = nil
    }
}

extension HAR.Entry {
    /// Convert an entry back into `HTTPURLResponse` and body `Data` for playback.
    public func toURLResponse() throws -> (HTTPURLResponse, Data) {
        guard let url = URL(string: request.url) else {
            throw ReplayError.invalidURL(request.url)
        }

        var headers: [String: String] = [:]
        for header in response.headers {
            headers[header.name] = header.value
        }

        guard
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: response.httpVersion,
                headerFields: headers
            )
        else {
            throw ReplayError.invalidResponse
        }

        let data: Data
        if let text = response.content.text {
            if response.content.encoding == "base64" {
                guard let decoded = Data(base64Encoded: text) else {
                    throw ReplayError.invalidBase64(text)
                }
                data = decoded
            } else {
                data = text.data(using: .utf8) ?? Data()
            }
        } else {
            data = Data()
        }

        return (httpResponse, data)
    }
}
