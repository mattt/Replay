import Foundation

/// Filters transform HAR entries to remove or redact sensitive data before
/// they are persisted to disk or inspected.
public enum Filter: Sendable {
    /// Redacts HTTP header values (in both the request and response) whose names match `names`.
    ///
    /// Header name matching is expected to be performed case-insensitively by storing `names`
    /// in lowercase (see `Filter.headers(removing:replacement:)`).
    case headers(names: Set<String>, replacement: String)

    /// Redacts URL query parameter values (in the request) whose names match `names`.
    case queryParameters(names: Set<String>, replacement: String)

    /// Replaces occurrences of `pattern` with `replacement` in request/response bodies when present.
    ///
    /// This is a simple string replacement and is best suited to text formats (JSON, XML, etc).
    case body(pattern: String, replacement: String)

    /// Applies an arbitrary async transformation to an entry.
    case custom(@Sendable (HAR.Entry) async -> HAR.Entry)

    /// Applies the filter to a HAR entry.
    ///
    /// - Parameter entry: The entry to transform.
    /// - Returns: The transformed entry.
    public func apply(to entry: HAR.Entry) async -> HAR.Entry {
        switch self {
        case .headers(let names, let replacement):
            var modified = entry

            // Filter request headers
            modified.request.headers = entry.request.headers.map { header in
                if names.contains(header.name.lowercased()) {
                    return HAR.Header(
                        name: header.name, value: replacement, comment: header.comment)
                }
                return header
            }

            // Filter response headers
            modified.response.headers = entry.response.headers.map { header in
                if names.contains(header.name.lowercased()) {
                    return HAR.Header(
                        name: header.name, value: replacement, comment: header.comment)
                }
                return header
            }

            return modified

        case .queryParameters(let names, let replacement):
            var modified = entry

            modified.request.queryString = entry.request.queryString.map { param in
                if names.contains(param.name) {
                    return HAR.QueryParameter(
                        name: param.name,
                        value: replacement,
                        comment: param.comment
                    )
                }
                return param
            }

            return modified

        case .body(let pattern, let replacement):
            var modified = entry

            // Filter request body
            if let postData = entry.request.postData,
                let text = postData.text
            {
                let filtered = text.replacingOccurrences(of: pattern, with: replacement)
                modified.request.postData = HAR.PostData(
                    mimeType: postData.mimeType,
                    params: postData.params,
                    text: filtered,
                    comment: postData.comment
                )
            }

            // Filter response body
            if let text = entry.response.content.text {
                let filtered = text.replacingOccurrences(of: pattern, with: replacement)
                modified.response.content = HAR.Content(
                    size: entry.response.content.size,
                    compression: entry.response.content.compression,
                    mimeType: entry.response.content.mimeType,
                    text: filtered,
                    encoding: entry.response.content.encoding,
                    comment: entry.response.content.comment
                )
            }

            return modified

        case .custom(let transform):
            return await transform(entry)
        }
    }
}

// MARK: - Convenience Extensions

extension Filter {
    /// Creates a filter that redacts the specified HTTP headers.
    ///
    /// Header name matching is case-insensitive.
    ///
    /// - Parameters:
    ///   - names: Header names to redact.
    ///   - replacement: The replacement value to use.
    public static func headers(_ names: String..., replacement: String = "[FILTERED]") -> Self {
        .headers(removing: names, replacement: replacement)
    }

    /// Creates a filter that redacts the specified HTTP headers.
    ///
    /// Header name matching is case-insensitive.
    ///
    /// - Parameters:
    ///   - headers: Header names to redact.
    ///   - replacement: The replacement value to use.
    public static func headers(removing headers: [String], replacement: String = "[FILTERED]")
        -> Self
    {
        .headers(names: Set(headers.map { $0.lowercased() }), replacement: replacement)
    }

    /// Keeps only the specified HTTP headers (in both the request and response), removing all others.
    ///
    /// Header name matching is case-insensitive.
    public static func headers(keeping headers: [String]) -> Self {
        let allowlist = Set(headers.map { $0.lowercased() })
        return .custom { entry in
            var modified = entry
            modified.request.headers = entry.request.headers.filter { header in
                allowlist.contains(header.name.lowercased())
            }
            modified.response.headers = entry.response.headers.filter { header in
                allowlist.contains(header.name.lowercased())
            }
            return modified
        }
    }

    /// Keeps only the specified HTTP headers (in both the request and response), removing all others.
    ///
    /// Header name matching is case-insensitive.
    public static func headers(keeping headers: String...) -> Self {
        .headers(keeping: headers)
    }

    /// Creates a filter that redacts the specified URL query parameters.
    ///
    /// Query parameter name matching is case-sensitive
    /// and uses exact string equality.
    ///
    /// - Parameters:
    ///   - names: Parameter names to redact.
    ///   - replacement: The replacement value to use.
    public static func queryParameters(_ names: String..., replacement: String = "[FILTERED]") -> Self {
        .queryParameters(removing: names, replacement: replacement)
    }

    /// Creates a filter that redacts the specified URL query parameters.
    ///
    /// Query parameter name matching is case-sensitive
    /// and uses exact string equality.
    ///
    /// - Parameters:
    ///   - parameters: Parameter names to redact.
    ///   - replacement: The replacement value to use.
    public static func queryParameters(
        removing parameters: [String],
        replacement: String = "[FILTERED]"
    ) -> Self {
        .queryParameters(names: Set(parameters), replacement: replacement)
    }

    /// Keeps only the specified URL query parameters (in the request), removing all others.
    ///
    /// Query parameter name matching is case-sensitive and uses exact string equality.
    public static func queryParameters(keeping parameters: [String]) -> Self {
        let allowlist = Set(parameters)
        return .custom { entry in
            var modified = entry
            modified.request.queryString = entry.request.queryString.filter { param in
                allowlist.contains(param.name)
            }
            return modified
        }
    }

    /// Keeps only the specified URL query parameters (in the request), removing all others.
    ///
    /// Query parameter name matching is case-sensitive and uses exact string equality.
    public static func queryParameters(keeping parameters: String...) -> Self {
        .queryParameters(keeping: parameters)
    }

    /// Creates a filter that replaces occurrences of a pattern in request and response bodies.
    ///
    /// This filter performs a simple string replacement.
    /// It is best suited to text formats such as JSON or XML.
    ///
    /// - Parameters:
    ///   - pattern: The string to replace.
    ///   - replacement: The replacement string to use.
    public static func body(replacing pattern: String, with replacement: String = "[FILTERED]")
        -> Self
    {
        .body(pattern: pattern, replacement: replacement)
    }

    /// Creates a filter that decodes JSON bodies,
    /// transforms the decoded value,
    /// and writes the transformed value back as JSON.
    ///
    /// This filter operates on request bodies (`postData.text`)
    /// and response bodies (`content.text`) when present.
    ///
    /// - Parameters:
    ///   - type: The `Codable` type to decode from JSON.
    ///   - transform: A transformation applied to decoded values.
    public static func body<T: Codable>(
        decoding type: T.Type,
        transform: @escaping @Sendable (T) -> T
    ) -> Self {
        .custom { entry in
            var modified = entry
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            func transformContent(_ text: String, encoding: String?) -> (String, String?)? {
                // Determine data from text based on encoding
                var data: Data?
                if encoding == "base64" {
                    data = Data(base64Encoded: text)
                } else {
                    data = text.data(using: .utf8)
                    // If not base64 explicitly, but utf8 conversion fails (unlikely), try base64 fallback?
                    // HAR 1.2 "text" is string. If encoding is not set, it is just text.
                    // If the text happens to be base64 but encoding is not set, we treat it as text string (which might fail JSON decode)
                }

                guard let originalData = data else { return nil }

                // Decode
                guard let decoded = try? decoder.decode(T.self, from: originalData) else {
                    return nil
                }

                // Transform
                let transformed = transform(decoded)

                // Encode
                guard let encodedData = try? encoder.encode(transformed) else {
                    return nil
                }

                // Convert back to string
                if let string = String(data: encodedData, encoding: .utf8) {
                    return (string, nil)
                } else {
                    return (encodedData.base64EncodedString(), "base64")
                }
            }

            // Request Body
            if let postData = modified.request.postData, let text = postData.text {
                // PostData usually doesn't have encoding field, try as is (UTF-8 implied for JSON)
                if let (newText, _) = transformContent(text, encoding: nil) {
                    modified.request.postData?.text = newText
                }
            }

            // Response Body
            if let text = modified.response.content.text {
                if let (newText, newEncoding) = transformContent(
                    text, encoding: modified.response.content.encoding)
                {
                    modified.response.content.text = newText
                    modified.response.content.encoding = newEncoding
                }
            }

            return modified
        }
    }
}
