import Foundation

/// A lightweight HTTP stub used for in-memory playback without a HAR file.
public struct Stub: Sendable {

    /// HTTP request method.
    public enum Method: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
        case get
        case post
        case put
        case delete
        case patch
        case head
        case options
        case trace
        case connect
        case custom(String)

        public init(rawValue: String) {
            switch rawValue.uppercased() {
            case "GET": self = .get
            case "POST": self = .post
            case "PUT": self = .put
            case "DELETE": self = .delete
            case "PATCH": self = .patch
            case "HEAD": self = .head
            case "OPTIONS": self = .options
            case "TRACE": self = .trace
            case "CONNECT": self = .connect
            default: self = .custom(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .get: return "GET"
            case .post: return "POST"
            case .put: return "PUT"
            case .delete: return "DELETE"
            case .patch: return "PATCH"
            case .head: return "HEAD"
            case .options: return "OPTIONS"
            case .trace: return "TRACE"
            case .connect: return "CONNECT"
            case .custom(let method): return method
            }
        }

        public var description: String {
            rawValue
        }

        public static func == (lhs: Method, rhs: Method) -> Bool {
            lhs.rawValue.caseInsensitiveCompare(rhs.rawValue) == .orderedSame
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(rawValue.uppercased())
        }
    }

    public var method: Method
    public var url: URL
    public var status: Int
    public var headers: [String: String]
    public var body: Data?

    /// Initialize a stub with a specific method and URL.
    /// - Parameters:
    ///   - method: HTTP method (default: .get).
    ///   - url: Request URL.
    ///   - status: HTTP status code (default: 200).
    ///   - headers: HTTP headers.
    ///   - body: Response body data.
    public init(
        _ method: Method = .get,
        _ url: URL,
        status: Int = 200,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.url = url
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// Initialize a stub with a specific method and URL string.
    /// - Parameters:
    ///   - method: HTTP method (default: .get).
    ///   - url: Request URL string.
    ///   - status: HTTP status code (default: 200).
    ///   - headers: HTTP headers.
    ///   - body: Response body data.
    public init(
        _ method: Method = .get,
        _ url: String,
        status: Int = 200,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        guard let u = URL(string: url) else {
            fatalError("Invalid URL string: \(url)")
        }
        self.init(method, u, status: status, headers: headers, body: body)
    }

    /// Initialize a stub with a String body (UTF-8).
    /// - Parameters:
    ///   - method: HTTP method (default: .get).
    ///   - url: Request URL.
    ///   - status: HTTP status code (default: 200).
    ///   - headers: HTTP headers.
    ///   - body: Response body string (encoded as UTF-8).
    public init(
        _ method: Method = .get,
        _ url: URL,
        status: Int = 200,
        headers: [String: String] = [:],
        body: String
    ) {
        self.init(
            method,
            url,
            status: status,
            headers: headers,
            body: body.data(using: .utf8)
        )
    }

    /// Initialize a stub with a String body (UTF-8) and URL string.
    /// - Parameters:
    ///   - method: HTTP method (default: .get).
    ///   - url: Request URL string.
    ///   - status: HTTP status code (default: 200).
    ///   - headers: HTTP headers.
    ///   - body: Response body string (encoded as UTF-8).
    public init(
        _ method: Method = .get,
        _ url: String,
        status: Int = 200,
        headers: [String: String] = [:],
        body: String
    ) {
        guard let u = URL(string: url) else {
            fatalError("Invalid URL string: \(url)")
        }
        self.init(
            method,
            u,
            status: status,
            headers: headers,
            body: body.data(using: .utf8)
        )
    }
}

// MARK: - Convenience Factory Methods

extension Stub {

    /// Create a GET stub.
    public static func get(
        _ url: String,
        _ status: Int,
        _ headers: [String: String],
        _ body: () -> String
    ) -> Stub {
        Stub(
            .get,
            url,
            status: status,
            headers: headers,
            body: body().data(using: .utf8)
        )
    }

    /// Create a POST stub.
    public static func post(
        _ url: String,
        _ status: Int,
        _ headers: [String: String],
        _ body: () -> String
    ) -> Stub {
        Stub(
            .post,
            url,
            status: status,
            headers: headers,
            body: body().data(using: .utf8)
        )
    }

    /// Create a PUT stub.
    public static func put(
        _ url: String,
        _ status: Int,
        _ headers: [String: String],
        _ body: () -> String
    ) -> Stub {
        Stub(
            .put,
            url,
            status: status,
            headers: headers,
            body: body().data(using: .utf8)
        )
    }

    /// Create a DELETE stub.
    public static func delete(
        _ url: String,
        _ status: Int,
        _ headers: [String: String],
        _ body: () -> String
    ) -> Stub {
        Stub(
            .delete,
            url,
            status: status,
            headers: headers,
            body: body().data(using: .utf8)
        )
    }

    /// Create a PATCH stub.
    public static func patch(
        _ url: String,
        _ status: Int,
        _ headers: [String: String],
        _ body: () -> String
    ) -> Stub {
        Stub(
            .patch,
            url,
            status: status,
            headers: headers,
            body: body().data(using: .utf8)
        )
    }

    /// Create a HEAD stub.
    public static func head(
        _ url: String,
        _ status: Int,
        _ headers: [String: String],
    ) -> Stub {
        Stub(
            .head,
            url,
            status: status,
            headers: headers,
            body: nil
        )
    }

    /// Create a OPTIONS stub.
    public static func options(
        _ url: String,
        _ status: Int,
        _ headers: [String: String],
    ) -> Stub {
        Stub(
            .options,
            url,
            status: status,
            headers: headers,
            body: nil
        )
    }

    /// Create a TRACE stub.
    public static func trace(
        _ url: String,
        _ status: Int,
        _ headers: [String: String],
    ) -> Stub {
        Stub(
            .trace,
            url,
            status: status,
            headers: headers,
            body: nil
        )
    }

    /// Create a CONNECT stub.
    public static func connect(
        _ url: String,
        _ status: Int,
        _ headers: [String: String],
    ) -> Stub {
        Stub(
            .connect,
            url,
            status: status,
            headers: headers,
            body: nil
        )
    }
}
