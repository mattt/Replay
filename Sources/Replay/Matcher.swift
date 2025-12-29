import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Strategy for matching incoming requests to recorded HAR entries.
public enum Matcher: Sendable {
    /// Matches HTTP method
    /// (for example, `GET` or `POST`).
    case method

    /// Matches the full absolute URL string (`URL.absoluteString`), including scheme, port, query, and fragment.
    ///
    /// - Warning: This matcher is **strict** and can cause unexpected mismatches if your URLs
    ///   contain volatile query items (pagination cursors, timestamps, cache-busters) or if query
    ///   items are emitted in a different order.
    ///
    ///   If that happens, prefer composing matchers like `.method` + `.path` (+ `.query` or `.headers(...)`)
    ///   instead of matching the entire URL string.
    case url

    /// Matches URL host
    /// (for example, `api.example.com`).
    case host

    /// Matches URL path
    /// (for example, `/v1/users/42`).
    case path

    /// Matches URL query items (`URLComponents.queryItems`).
    ///
    /// - Important: This matcher is **not order-sensitive**.
    ///   `?a=1&b=2` matches `?b=2&a=1`.
    case query

    /// Matches URL fragment (`#fragment`).
    case fragment

    /// Matches the values of the specified HTTP request headers.
    ///
    /// Header name lookup uses `URLRequest.value(forHTTPHeaderField:)` semantics.
    case headers([String])

    /// Matches the raw HTTP body bytes (`URLRequest.httpBody`).
    case body

    /// Escape hatch for custom matching logic.
    /// Compares an incoming request against a candidate request (typically from a recorded entry).
    case custom(@Sendable (_ request: URLRequest, _ candidate: URLRequest) -> Bool)

    func test(_ request: URLRequest, _ candidate: URLRequest) -> Bool {
        switch self {
        case .method:
            return request.httpMethod?.uppercased() == candidate.httpMethod?.uppercased()

        case .url:
            return request.url?.absoluteString == candidate.url?.absoluteString

        case .host:
            return request.url?.host == candidate.url?.host

        case .path:
            return request.url?.path == candidate.url?.path

        case .query:
            guard let url1 = request.url,
                let url2 = candidate.url
            else { return false }

            let components1 = URLComponents(url: url1, resolvingAgainstBaseURL: true)
            let components2 = URLComponents(url: url2, resolvingAgainstBaseURL: true)
            return normalizedQueryItems(components1?.queryItems) == normalizedQueryItems(components2?.queryItems)

        case .fragment:
            return request.url?.fragment == candidate.url?.fragment

        case .headers(let names):
            for name in names {
                if request.value(forHTTPHeaderField: name)
                    != candidate.value(forHTTPHeaderField: name)
                {
                    return false
                }
            }
            return true

        case .body:
            return request.httpBody == candidate.httpBody

        case .custom(let block):
            return block(request, candidate)
        }
    }

    private func normalizedQueryItems(_ items: [URLQueryItem]?) -> [NormalizedQueryItem] {
        let normalized = (items ?? []).map { NormalizedQueryItem($0) }
        return normalized.sorted()
    }

    private struct NormalizedQueryItem: Comparable, Sendable {
        let name: String
        let value: String?

        init(_ item: URLQueryItem) {
            self.name = item.name
            self.value = item.value
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            switch (lhs.value, rhs.value) {
            case (nil, nil): return false
            case (nil, _?): return true
            case (_?, nil): return false
            case (let l?, let r?): return l < r
            }
        }
    }
}

// MARK: -

extension Array where Element == Matcher {
    /// Default matching strategy: HTTP method + full URL.
    ///
    /// This is the strictest matcher set and will treat changes in scheme, host/port, path,
    /// query ordering, or fragment as mismatches.
    public static var `default`: [Matcher] {
        [.method, .url]
    }

    /// Returns whether all matchers match `request` against itself.
    ///
    /// This is used by capture as an opt-in filter.
    public func matches(_ request: URLRequest) -> Bool {
        for matcher in self {
            if !matcher.test(request, request) {
                return false
            }
        }
        return true
    }

    /// Finds the first entry whose request matches according to all matchers.
    public func firstMatch(for request: URLRequest, in entries: [HAR.Entry]) -> HAR.Entry? {
        for entry in entries {
            guard let entryURL = URL(string: entry.request.url) else { continue }

            var entryRequest = URLRequest(url: entryURL)
            entryRequest.httpMethod = entry.request.method
            for header in entry.request.headers {
                entryRequest.setValue(header.value, forHTTPHeaderField: header.name)
            }
            if let postData = entry.request.postData,
                let text = postData.text
            {
                // HAR `postData.text` is stored as UTF-8 for text payloads.
                // For non-text payloads, Replay currently stores base64 in `text` without an
                // explicit encoding marker, so body matching is best-effort.
                entryRequest.httpBody = text.data(using: .utf8)
            }

            if matches(request, entryRequest) {
                return entry
            }
        }

        return nil
    }

    private func matches(_ request: URLRequest, _ candidate: URLRequest) -> Bool {
        for matcher in self {
            if !matcher.test(request, candidate) {
                return false
            }
        }
        return true
    }
}
