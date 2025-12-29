import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("Matcher Tests")
struct MatcherTests {

    // MARK: - Method Matcher Tests

    @Suite("Method Matcher")
    struct MethodMatcherTests {
        @Test("matches when HTTP methods are equal")
        func matchesEqualMethods() {
            let request1 = makeRequest(method: "GET", urlString: "https://example.com")
            let request2 = makeRequest(method: "GET", urlString: "https://different.com")

            let matchers: [Matcher] = [.method]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when HTTP methods differ")
        func doesNotMatchDifferentMethods() {
            let request1 = makeRequest(method: "GET", urlString: "https://example.com")
            let request2 = makeRequest(method: "POST", urlString: "https://example.com")

            let matchers: [Matcher] = [.method]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches after URLRequest normalizes method to uppercase")
        func matchesNormalizedMethods() {
            let request1 = makeRequest(method: "GET", urlString: "https://example.com")
            let request2 = makeRequest(method: "get", urlString: "https://example.com")

            let matchers: [Matcher] = [.method]
            #expect(matchers.matches(request1, request2))
        }
    }

    // MARK: - URL Matcher Tests

    @Suite("URL Matcher")
    struct URLMatcherTests {
        @Test("matches when URLs are equal")
        func matchesEqualURLs() {
            let request1 = makeRequest(urlString: "https://example.com/path?query=value")
            let request2 = makeRequest(urlString: "https://example.com/path?query=value")

            let matchers: [Matcher] = [.url]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when URLs differ")
        func doesNotMatchDifferentURLs() {
            let request1 = makeRequest(urlString: "https://example.com/path1")
            let request2 = makeRequest(urlString: "https://example.com/path2")

            let matchers: [Matcher] = [.url]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("does not match when query strings differ")
        func doesNotMatchDifferentQueryStrings() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1")
            let request2 = makeRequest(urlString: "https://example.com/path?a=2")

            let matchers: [Matcher] = [.url]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("does not match when schemes differ")
        func doesNotMatchDifferentSchemes() {
            let request1 = makeRequest(urlString: "https://example.com/path")
            let request2 = makeRequest(urlString: "http://example.com/path")

            let matchers: [Matcher] = [.url]
            #expect(!matchers.matches(request1, request2))
        }
    }

    // MARK: - Host Matcher Tests

    @Suite("Host Matcher")
    struct HostMatcherTests {
        @Test("matches when hosts are equal")
        func matchesEqualHosts() {
            let request1 = makeRequest(urlString: "https://api.example.com/v1/users")
            let request2 = makeRequest(urlString: "https://api.example.com/v2/posts")

            let matchers: [Matcher] = [.host]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when hosts differ")
        func doesNotMatchDifferentHosts() {
            let request1 = makeRequest(urlString: "https://api.example.com/path")
            let request2 = makeRequest(urlString: "https://api.other.com/path")

            let matchers: [Matcher] = [.host]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches regardless of scheme")
        func matchesRegardlessOfScheme() {
            let request1 = makeRequest(urlString: "https://example.com/path")
            let request2 = makeRequest(urlString: "http://example.com/path")

            let matchers: [Matcher] = [.host]
            #expect(matchers.matches(request1, request2))
        }

        @Test("matches regardless of port")
        func matchesRegardlessOfPort() {
            let request1 = makeRequest(urlString: "https://example.com:443/path")
            let request2 = makeRequest(urlString: "https://example.com:8443/path")

            let matchers: [Matcher] = [.host]
            #expect(matchers.matches(request1, request2))
        }
    }

    // MARK: - Path Matcher Tests

    @Suite("Path Matcher")
    struct PathMatcherTests {
        @Test("matches when paths are equal")
        func matchesEqualPaths() {
            let request1 = makeRequest(urlString: "https://example.com/api/v1/users")
            let request2 = makeRequest(urlString: "https://different.com/api/v1/users")

            let matchers: [Matcher] = [.path]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when paths differ")
        func doesNotMatchDifferentPaths() {
            let request1 = makeRequest(urlString: "https://example.com/api/v1/users")
            let request2 = makeRequest(urlString: "https://example.com/api/v2/users")

            let matchers: [Matcher] = [.path]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches regardless of query string")
        func matchesRegardlessOfQueryString() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1")
            let request2 = makeRequest(urlString: "https://example.com/path?b=2")

            let matchers: [Matcher] = [.path]
            #expect(matchers.matches(request1, request2))
        }

        @Test("matches empty paths")
        func matchesEmptyPaths() {
            let request1 = makeRequest(urlString: "https://example.com")
            let request2 = makeRequest(urlString: "https://different.com")

            let matchers: [Matcher] = [.path]
            #expect(matchers.matches(request1, request2))
        }
    }

    // MARK: - Query Matcher Tests

    @Suite("Query Matcher")
    struct QueryMatcherTests {
        @Test("matches when query items are equal")
        func matchesEqualQueryItems() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1&b=2")
            let request2 = makeRequest(urlString: "https://different.com/other?a=1&b=2")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when query items differ")
        func doesNotMatchDifferentQueryItems() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1")
            let request2 = makeRequest(urlString: "https://example.com/path?a=2")

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("does not match when query item is missing")
        func doesNotMatchMissingQueryItem() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1&b=2")
            let request2 = makeRequest(urlString: "https://example.com/path?a=1")

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches when both have no query")
        func matchesBothNoQuery() {
            let request1 = makeRequest(urlString: "https://example.com/path")
            let request2 = makeRequest(urlString: "https://different.com/other")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("query order does not matter for matching")
        func queryOrderDoesNotMatter() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1&b=2")
            let request2 = makeRequest(urlString: "https://example.com/path?b=2&a=1")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("matches query items with nil values")
        func matchesQueryItemsWithNilValues() {
            let request1 = makeRequest(urlString: "https://example.com/path?key")
            let request2 = makeRequest(urlString: "https://example.com/path?key")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when one query item has value and other has nil")
        func doesNotMatchValueVsNil() {
            let request1 = makeRequest(urlString: "https://example.com/path?key")
            let request2 = makeRequest(urlString: "https://example.com/path?key=value")

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches empty query string vs no query")
        func matchesEmptyQueryStringVsNoQuery() {
            let request1 = makeRequest(urlString: "https://example.com/path?")
            let request2 = makeRequest(urlString: "https://example.com/path")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("matches multiple query items with same name")
        func matchesDuplicateQueryParameterNames() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1&a=2")
            let request2 = makeRequest(urlString: "https://example.com/path?a=2&a=1")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when duplicate parameter counts differ")
        func doesNotMatchDifferentDuplicateCounts() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1&a=2")
            let request2 = makeRequest(urlString: "https://example.com/path?a=1")

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("does not match when request has nil URL")
        func doesNotMatchWhenRequestHasNilURL() {
            let request1 = URLRequest(url: URL(string: "https://example.com/path?a=1")!)
            var request2 = URLRequest(url: URL(string: "https://example.com/path?a=1")!)
            request2.url = nil

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("does not match when candidate has nil URL")
        func doesNotMatchWhenCandidateHasNilURL() {
            var request1 = URLRequest(url: URL(string: "https://example.com/path?a=1")!)
            let request2 = URLRequest(url: URL(string: "https://example.com/path?a=1")!)
            request1.url = nil

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches URL-encoded query values")
        func matchesURLEncodedQueryValues() {
            let request1 = makeRequest(urlString: "https://example.com/path?q=hello%20world")
            let request2 = makeRequest(urlString: "https://example.com/path?q=hello%20world")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("matches query parameter names case-sensitively")
        func matchesQueryParameterNamesCaseSensitively() {
            let request1 = makeRequest(urlString: "https://example.com/path?Key=value")
            let request2 = makeRequest(urlString: "https://example.com/path?key=value")

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches query parameter values case-sensitively")
        func matchesQueryParameterValuesCaseSensitively() {
            let request1 = makeRequest(urlString: "https://example.com/path?key=Value")
            let request2 = makeRequest(urlString: "https://example.com/path?key=value")

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches complex query with multiple parameters and values")
        func matchesComplexQuery() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1&b=2&c=3&d=4")
            let request2 = makeRequest(urlString: "https://example.com/path?d=4&c=3&b=2&a=1")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("matches query with special characters")
        func matchesQueryWithSpecialCharacters() {
            let request1 = makeRequest(urlString: "https://example.com/path?email=user%40example.com&token=abc123")
            let request2 = makeRequest(urlString: "https://example.com/path?token=abc123&email=user%40example.com")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("normalizes query items by sorting name then value")
        func normalizesQueryItemsBySorting() {
            // Test that normalization correctly sorts items with same name but different values
            let request1 = makeRequest(urlString: "https://example.com/path?a=2&a=1&b=3")
            let request2 = makeRequest(urlString: "https://example.com/path?a=1&a=2&b=3")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("normalizes query items with nil values before non-nil")
        func normalizesNilValuesBeforeNonNil() {
            // Test that items with nil values are sorted before items with values
            let request1 = makeRequest(urlString: "https://example.com/path?key=value&flag&other=test")
            let request2 = makeRequest(urlString: "https://example.com/path?flag&key=value&other=test")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("matches duplicate parameters with mixed nil and non-nil values")
        func matchesDuplicateParametersWithMixedNilAndNonNil() {
            let request1 = makeRequest(urlString: "https://example.com/path?key&key=value&key=other")
            let request2 = makeRequest(urlString: "https://example.com/path?key=other&key&key=value")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when duplicate parameters have different value sets")
        func doesNotMatchDifferentDuplicateValueSets() {
            let request1 = makeRequest(urlString: "https://example.com/path?key=1&key=2")
            let request2 = makeRequest(urlString: "https://example.com/path?key=1&key=3")

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("handles URLComponents with nil queryItems")
        func handlesURLComponentsWithNilQueryItems() {
            // Create a URL that might result in nil queryItems
            var components = URLComponents()
            components.scheme = "https"
            components.host = "example.com"
            components.path = "/path"
            // queryItems is nil, not empty array
            let url = components.url!

            let request1 = URLRequest(url: url)
            let request2 = makeRequest(urlString: "https://example.com/path")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("matches when both have nil queryItems from URLComponents")
        func matchesWhenBothHaveNilQueryItems() {
            var components1 = URLComponents()
            components1.scheme = "https"
            components1.host = "example.com"
            components1.path = "/path1"

            var components2 = URLComponents()
            components2.scheme = "https"
            components2.host = "example.com"
            components2.path = "/path2"

            let request1 = URLRequest(url: components1.url!)
            let request2 = URLRequest(url: components2.url!)

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("normalizes query items alphabetically by name")
        func normalizesQueryItemsAlphabeticallyByName() {
            // Test that items are sorted by name first
            let request1 = makeRequest(urlString: "https://example.com/path?z=last&a=first&m=middle")
            let request2 = makeRequest(urlString: "https://example.com/path?a=first&m=middle&z=last")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("normalizes query items by value when names are equal")
        func normalizesQueryItemsByValueWhenNamesEqual() {
            // Test that when names are equal, values are sorted
            let request1 = makeRequest(urlString: "https://example.com/path?key=zebra&key=apple&key=banana")
            let request2 = makeRequest(urlString: "https://example.com/path?key=apple&key=banana&key=zebra")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("handles query items with empty string values")
        func handlesQueryItemsWithEmptyStringValues() {
            let request1 = makeRequest(urlString: "https://example.com/path?key=&other=value")
            let request2 = makeRequest(urlString: "https://example.com/path?other=value&key=")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("distinguishes between empty string value and nil value")
        func distinguishesBetweenEmptyStringAndNilValue() {
            let request1 = makeRequest(urlString: "https://example.com/path?key")
            let request2 = makeRequest(urlString: "https://example.com/path?key=")

            let matchers: [Matcher] = [.query]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches complex query with duplicates and nil values")
        func matchesComplexQueryWithDuplicatesAndNilValues() {
            let request1 = makeRequest(urlString: "https://example.com/path?a=1&flag&a=2&b=test&flag&c=3")
            let request2 = makeRequest(urlString: "https://example.com/path?c=3&flag&a=2&b=test&a=1&flag")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }

        @Test("handles resolvingAgainstBaseURL behavior")
        func handlesResolvingAgainstBaseURLBehavior() {
            // Test that resolvingAgainstBaseURL: true works correctly
            let baseURL = URL(string: "https://example.com/base")!
            let relativeURL = URL(string: "path?a=1&b=2", relativeTo: baseURL)!

            let request1 = URLRequest(url: relativeURL)
            let request2 = makeRequest(urlString: "https://example.com/base/path?a=1&b=2")

            let matchers: [Matcher] = [.query]
            #expect(matchers.matches(request1, request2))
        }
    }

    // MARK: - Headers Matcher Tests

    @Suite("Headers Matcher")
    struct HeadersMatcherTests {
        @Test("matches when specified headers are equal")
        func matchesEqualHeaders() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request1.setValue("Bearer token", forHTTPHeaderField: "Authorization")

            var request2 = makeRequest(urlString: "https://different.com")
            request2.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request2.setValue("Bearer token", forHTTPHeaderField: "Authorization")

            let matchers: [Matcher] = [.headers(["Content-Type", "Authorization"])]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when specified header values differ")
        func doesNotMatchDifferentHeaderValues() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.setValue("application/json", forHTTPHeaderField: "Content-Type")

            var request2 = makeRequest(urlString: "https://example.com")
            request2.setValue("text/plain", forHTTPHeaderField: "Content-Type")

            let matchers: [Matcher] = [.headers(["Content-Type"])]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("does not match when specified header is missing")
        func doesNotMatchMissingHeader() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.setValue("Bearer token", forHTTPHeaderField: "Authorization")

            let request2 = makeRequest(urlString: "https://example.com")

            let matchers: [Matcher] = [.headers(["Authorization"])]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("ignores headers not in the list")
        func ignoresOtherHeaders() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request1.setValue("extra1", forHTTPHeaderField: "X-Extra")

            var request2 = makeRequest(urlString: "https://example.com")
            request2.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request2.setValue("extra2", forHTTPHeaderField: "X-Extra")

            let matchers: [Matcher] = [.headers(["Content-Type"])]
            #expect(matchers.matches(request1, request2))
        }

        @Test("matches with empty header list")
        func matchesWithEmptyHeaderList() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.setValue("value1", forHTTPHeaderField: "X-Custom")

            var request2 = makeRequest(urlString: "https://different.com")
            request2.setValue("value2", forHTTPHeaderField: "X-Custom")

            let matchers: [Matcher] = [.headers([])]
            #expect(matchers.matches(request1, request2))
        }

        @Test("header matching is case-insensitive for names")
        func headerNamesCaseInsensitive() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.setValue("application/json", forHTTPHeaderField: "content-type")

            var request2 = makeRequest(urlString: "https://example.com")
            request2.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let matchers: [Matcher] = [.headers(["CONTENT-TYPE"])]
            #expect(matchers.matches(request1, request2))
        }
    }

    // MARK: - Body Matcher Tests

    @Suite("Body Matcher")
    struct BodyMatcherTests {
        @Test("matches when bodies are equal")
        func matchesEqualBodies() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.httpBody = "test body".data(using: .utf8)

            var request2 = makeRequest(urlString: "https://different.com")
            request2.httpBody = "test body".data(using: .utf8)

            let matchers: [Matcher] = [.body]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when bodies differ")
        func doesNotMatchDifferentBodies() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.httpBody = "body 1".data(using: .utf8)

            var request2 = makeRequest(urlString: "https://example.com")
            request2.httpBody = "body 2".data(using: .utf8)

            let matchers: [Matcher] = [.body]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches when both bodies are nil")
        func matchesBothNilBodies() {
            let request1 = makeRequest(urlString: "https://example.com")
            let request2 = makeRequest(urlString: "https://different.com")

            let matchers: [Matcher] = [.body]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when one body is nil")
        func doesNotMatchOneNilBody() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.httpBody = "body".data(using: .utf8)

            let request2 = makeRequest(urlString: "https://example.com")

            let matchers: [Matcher] = [.body]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches binary data")
        func matchesBinaryData() {
            var request1 = makeRequest(urlString: "https://example.com")
            request1.httpBody = Data([0x00, 0x01, 0x02, 0xFF])

            var request2 = makeRequest(urlString: "https://different.com")
            request2.httpBody = Data([0x00, 0x01, 0x02, 0xFF])

            let matchers: [Matcher] = [.body]
            #expect(matchers.matches(request1, request2))
        }
    }

    // MARK: - Custom Matcher Tests

    @Suite("Custom Matcher")
    struct CustomMatcherTests {
        @Test("uses custom closure for matching")
        func usesCustomClosure() {
            let request1 = makeRequest(urlString: "https://example.com/users/123")
            let request2 = makeRequest(urlString: "https://example.com/users/456")

            let matchers: [Matcher] = [
                .custom { request, candidate in
                    guard let path1 = request.url?.path,
                        let path2 = candidate.url?.path
                    else { return false }
                    return path1.hasPrefix("/users/") && path2.hasPrefix("/users/")
                }
            ]
            #expect(matchers.matches(request1, request2))
        }

        @Test("custom matcher can return false")
        func customMatcherReturnsFalse() {
            let request1 = makeRequest(urlString: "https://example.com")
            let request2 = makeRequest(urlString: "https://example.com")

            let matchers: [Matcher] = [.custom { _, _ in false }]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("custom matcher receives correct requests")
        func customMatcherReceivesCorrectRequests() {
            var request1 = makeRequest(method: "POST", urlString: "https://example.com/a")
            request1.httpBody = "body1".data(using: .utf8)

            var request2 = makeRequest(method: "GET", urlString: "https://example.com/b")
            request2.httpBody = "body2".data(using: .utf8)

            let matchers: [Matcher] = [
                .custom { request, candidate in
                    request.httpMethod == "POST" && request.url?.path == "/a"
                        && candidate.httpMethod == "GET" && candidate.url?.path == "/b"
                }
            ]
            #expect(matchers.matches(request1, request2))
        }
    }

    // MARK: - Array Extension Tests

    @Suite("Array Extension")
    struct ArrayExtensionTests {
        @Test("default returns method and url matchers")
        func defaultMatchers() {
            let matchers: [Matcher] = .default

            let request1 = makeRequest(method: "GET", urlString: "https://example.com/path")
            let request2 = makeRequest(method: "GET", urlString: "https://example.com/path")
            let request3 = makeRequest(method: "POST", urlString: "https://example.com/path")
            let request4 = makeRequest(method: "GET", urlString: "https://example.com/other")

            #expect(matchers.matches(request1, request2))
            #expect(!matchers.matches(request1, request3))
            #expect(!matchers.matches(request1, request4))
        }

        @Test("matches with single request uses self-matching")
        func matchesSingleRequest() {
            let request = makeRequest(method: "GET", urlString: "https://example.com/path")
            let matchers: [Matcher] = [.method, .url]

            #expect(matchers.matches(request))
        }

        @Test("firstMatch finds matching entry")
        func firstMatchFindsEntry() {
            let entries = [
                makeTestEntry(method: "GET", urlString: "https://example.com/a"),
                makeTestEntry(method: "GET", urlString: "https://example.com/b"),
                makeTestEntry(method: "POST", urlString: "https://example.com/b"),
            ]

            let request = makeRequest(method: "GET", urlString: "https://example.com/b")
            let matchers: [Matcher] = .default

            let match = matchers.firstMatch(for: request, in: entries)

            #expect(match != nil)
            #expect(match?.request.url == "https://example.com/b")
            #expect(match?.request.method == "GET")
        }

        @Test("firstMatch returns nil when no match found")
        func firstMatchReturnsNil() {
            let entries = [
                makeTestEntry(method: "GET", urlString: "https://example.com/a"),
                makeTestEntry(method: "POST", urlString: "https://example.com/b"),
            ]

            let request = makeRequest(method: "DELETE", urlString: "https://example.com/c")
            let matchers: [Matcher] = .default

            let match = matchers.firstMatch(for: request, in: entries)

            #expect(match == nil)
        }

        @Test("firstMatch returns first of multiple matches")
        func firstMatchReturnsFirst() {
            let entries = [
                makeTestEntry(
                    method: "GET", urlString: "https://example.com/path", responseText: "first"),
                makeTestEntry(
                    method: "GET", urlString: "https://example.com/path", responseText: "second"),
            ]

            let request = makeRequest(method: "GET", urlString: "https://example.com/path")
            let matchers: [Matcher] = .default

            let match = matchers.firstMatch(for: request, in: entries)

            #expect(match?.response.content.text == "first")
        }

        @Test("firstMatch with header matcher")
        func firstMatchWithHeaders() {
            var entry1 = makeTestEntry(method: "GET", urlString: "https://example.com/api")
            entry1.request.headers = [HAR.Header(name: "Accept", value: "text/html")]

            var entry2 = makeTestEntry(method: "GET", urlString: "https://example.com/api")
            entry2.request.headers = [HAR.Header(name: "Accept", value: "application/json")]

            let entries = [entry1, entry2]

            var request = makeRequest(method: "GET", urlString: "https://example.com/api")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let matchers: [Matcher] = [.method, .url, .headers(["Accept"])]
            let match = matchers.firstMatch(for: request, in: entries)

            #expect(match?.request.headers.first { $0.name == "Accept" }?.value == "application/json")
        }

        @Test("firstMatch with body matcher")
        func firstMatchWithBody() {
            var entry1 = makeTestEntry(method: "POST", urlString: "https://example.com/api")
            entry1.request.postData = HAR.PostData(mimeType: "text/plain", text: "body1")

            var entry2 = makeTestEntry(method: "POST", urlString: "https://example.com/api")
            entry2.request.postData = HAR.PostData(mimeType: "text/plain", text: "body2")

            let entries = [entry1, entry2]

            var request = makeRequest(method: "POST", urlString: "https://example.com/api")
            request.httpBody = "body2".data(using: .utf8)

            let matchers: [Matcher] = [.method, .url, .body]
            let match = matchers.firstMatch(for: request, in: entries)

            #expect(match?.request.postData?.text == "body2")
        }

        @Test("multiple matchers all must pass")
        func multipleMatchersAllMustPass() {
            let request1 = makeRequest(method: "GET", urlString: "https://example.com/path")
            let request2 = makeRequest(method: "GET", urlString: "https://different.com/path")

            let matchers: [Matcher] = [.method, .host, .path]

            #expect(!matchers.matches(request1, request2))
        }

        @Test("empty matchers array always matches")
        func emptyMatchersArrayMatches() {
            let request1 = makeRequest(method: "GET", urlString: "https://example.com/a")
            let request2 = makeRequest(method: "POST", urlString: "https://different.com/b")

            let matchers: [Matcher] = []
            #expect(matchers.matches(request1, request2))
        }
    }

    // MARK: - Combined Matcher Tests

    @Suite("Combined Matchers")
    struct CombinedMatcherTests {
        @Test("host and path matcher ignores query")
        func hostAndPathIgnoresQuery() {
            let request1 = makeRequest(urlString: "https://api.example.com/v1/users?page=1")
            let request2 = makeRequest(urlString: "https://api.example.com/v1/users?page=2")

            let matchers: [Matcher] = [.host, .path]
            #expect(matchers.matches(request1, request2))
        }

        @Test("method, host, path, query for full matching without scheme")
        func fullMatchingWithoutScheme() {
            let request1 = makeRequest(
                method: "GET", urlString: "https://api.example.com/v1/users?page=1")
            let request2 = makeRequest(
                method: "GET", urlString: "http://api.example.com/v1/users?page=1")

            let matchers: [Matcher] = [.method, .host, .path, .query]
            #expect(matchers.matches(request1, request2))
        }
    }

    // MARK: - Fragment Matcher Tests

    @Suite("Fragment Matcher")
    struct FragmentMatcherTests {
        @Test("matches when fragments are equal")
        func matchesEqualFragments() {
            let request1 = makeRequest(urlString: "https://example.com/path#frag")
            let request2 = makeRequest(urlString: "https://different.com/other#frag")

            let matchers: [Matcher] = [.fragment]
            #expect(matchers.matches(request1, request2))
        }

        @Test("does not match when fragments differ")
        func doesNotMatchDifferentFragments() {
            let request1 = makeRequest(urlString: "https://example.com/path#frag1")
            let request2 = makeRequest(urlString: "https://example.com/path#frag2")

            let matchers: [Matcher] = [.fragment]
            #expect(!matchers.matches(request1, request2))
        }

        @Test("matches when both fragments are nil")
        func matchesNilFragments() {
            let request1 = makeRequest(urlString: "https://example.com/path")
            let request2 = makeRequest(urlString: "https://example.com/other")

            let matchers: [Matcher] = [.fragment]
            #expect(matchers.matches(request1, request2))
        }
    }
}

// MARK: - Test Helpers

private func makeRequest(method: String = "GET", urlString: String) -> URLRequest {
    var request = URLRequest(url: URL(string: urlString)!)
    request.httpMethod = method
    return request
}

private func makeTestEntry(
    method: String = "GET",
    urlString: String,
    responseText: String = "OK"
) -> HAR.Entry {
    let request = HAR.Request(
        method: method,
        url: urlString,
        httpVersion: "HTTP/1.1",
        headers: [],
        bodySize: 0
    )
    let content = HAR.Content(
        size: responseText.count,
        mimeType: "text/plain",
        text: responseText
    )
    let response = HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: responseText.count
    )
    return HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: request,
        response: response,
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}

private extension [Matcher] {
    func matches(_ request: URLRequest, _ candidate: URLRequest) -> Bool {
        for matcher in self {
            if !matcher.test(request, candidate) {
                return false
            }
        }
        return true
    }
}
