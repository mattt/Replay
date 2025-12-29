import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("Filter Tests")
struct FilterTests {

    // MARK: - Headers Filter Tests

    @Suite("Filter.headers Tests")
    struct HeadersFilterTests {
        @Test("redacts request headers by name")
        func redactsRequestHeaders() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [
                    HAR.Header(name: "Authorization", value: "Bearer secret-token"),
                    HAR.Header(name: "Content-Type", value: "application/json"),
                ],
                responseHeaders: []
            )

            let filter = Filter.headers(names: ["authorization"], replacement: "[REDACTED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.headers[0].value == "[REDACTED]")
            #expect(result.request.headers[1].value == "application/json")
        }

        @Test("redacts response headers by name")
        func redactsResponseHeaders() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [],
                responseHeaders: [
                    HAR.Header(name: "Set-Cookie", value: "session=abc123"),
                    HAR.Header(name: "Content-Length", value: "100"),
                ]
            )

            let filter = Filter.headers(names: ["set-cookie"], replacement: "[FILTERED]")
            let result = await filter.apply(to: entry)

            #expect(result.response.headers[0].value == "[FILTERED]")
            #expect(result.response.headers[1].value == "100")
        }

        @Test("header matching is case-insensitive")
        func caseInsensitiveMatching() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [
                    HAR.Header(name: "AUTHORIZATION", value: "secret1"),
                    HAR.Header(name: "Authorization", value: "secret2"),
                    HAR.Header(name: "authorization", value: "secret3"),
                ],
                responseHeaders: []
            )

            let filter = Filter.headers(names: ["authorization"], replacement: "[REDACTED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.headers[0].value == "[REDACTED]")
            #expect(result.request.headers[1].value == "[REDACTED]")
            #expect(result.request.headers[2].value == "[REDACTED]")
        }

        @Test("redacts multiple header names")
        func redactsMultipleHeaders() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [
                    HAR.Header(name: "Authorization", value: "Bearer token"),
                    HAR.Header(name: "X-API-Key", value: "api-key-123"),
                    HAR.Header(name: "Content-Type", value: "application/json"),
                ],
                responseHeaders: []
            )

            let filter = Filter.headers(
                names: ["authorization", "x-api-key"], replacement: "[FILTERED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.headers[0].value == "[FILTERED]")
            #expect(result.request.headers[1].value == "[FILTERED]")
            #expect(result.request.headers[2].value == "application/json")
        }

        @Test("preserves header name and comment")
        func preservesHeaderNameAndComment() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [
                    HAR.Header(name: "Authorization", value: "secret", comment: "Auth header")
                ],
                responseHeaders: []
            )

            let filter = Filter.headers(names: ["authorization"], replacement: "[REDACTED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.headers[0].name == "Authorization")
            #expect(result.request.headers[0].comment == "Auth header")
        }
    }

    // MARK: - Query Parameters Filter Tests

    @Suite("Filter.queryParameters Tests")
    struct QueryParametersFilterTests {
        @Test("redacts query parameter values by name")
        func redactsQueryParameters() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "api_key", value: "secret-key"),
                HAR.QueryParameter(name: "page", value: "1"),
            ])

            let filter = Filter.queryParameters(names: ["api_key"], replacement: "[FILTERED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString[0].value == "[FILTERED]")
            #expect(result.request.queryString[1].value == "1")
        }

        @Test("redacts multiple query parameters")
        func redactsMultipleQueryParameters() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "token", value: "abc123"),
                HAR.QueryParameter(name: "secret", value: "xyz789"),
                HAR.QueryParameter(name: "limit", value: "10"),
            ])

            let filter = Filter.queryParameters(
                names: ["token", "secret"], replacement: "[REMOVED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString[0].value == "[REMOVED]")
            #expect(result.request.queryString[1].value == "[REMOVED]")
            #expect(result.request.queryString[2].value == "10")
        }

        @Test("preserves parameter name and comment")
        func preservesParameterNameAndComment() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "api_key", value: "secret", comment: "API key param")
            ])

            let filter = Filter.queryParameters(names: ["api_key"], replacement: "[FILTERED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString[0].name == "api_key")
            #expect(result.request.queryString[0].comment == "API key param")
        }

        @Test("query parameter matching is case-sensitive")
        func caseSensitiveMatching() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "API_KEY", value: "value1"),
                HAR.QueryParameter(name: "api_key", value: "value2"),
            ])

            let filter = Filter.queryParameters(names: ["api_key"], replacement: "[FILTERED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString[0].value == "value1")
            #expect(result.request.queryString[1].value == "[FILTERED]")
        }
    }

    // MARK: - Allowlist / Keeping Tests

    @Suite("Filter allowlist convenience")
    struct AllowlistTests {
        @Test("headers(keeping:) keeps only allowed request headers")
        func headersKeepingRequestHeaders() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [
                    HAR.Header(name: "Authorization", value: "secret"),
                    HAR.Header(name: "Content-Type", value: "application/json"),
                    HAR.Header(name: "X-Debug", value: "1"),
                ],
                responseHeaders: []
            )

            let filter = Filter.headers(keeping: ["Content-Type"])
            let result = await filter.apply(to: entry)

            #expect(result.request.headers.map(\.name) == ["Content-Type"])
        }

        @Test("headers(keeping:) keeps only allowed response headers")
        func headersKeepingResponseHeaders() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [],
                responseHeaders: [
                    HAR.Header(name: "Set-Cookie", value: "a=b"),
                    HAR.Header(name: "Content-Type", value: "application/json"),
                    HAR.Header(name: "Content-Length", value: "100"),
                ]
            )

            let filter = Filter.headers(keeping: ["Content-Type", "Content-Length"])
            let result = await filter.apply(to: entry)

            #expect(result.response.headers.map(\.name) == ["Content-Type", "Content-Length"])
        }

        @Test("headers(keeping:) matches header names case-insensitively")
        func headersKeepingCaseInsensitive() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [
                    HAR.Header(name: "content-type", value: "application/json"),
                    HAR.Header(name: "X-Other", value: "ignore"),
                ],
                responseHeaders: []
            )

            let filter = Filter.headers(keeping: ["CONTENT-TYPE"])
            let result = await filter.apply(to: entry)

            #expect(result.request.headers.map(\.name) == ["content-type"])
        }

        @Test("queryParameters(keeping:) keeps only allowed query parameters")
        func queryParametersKeeping() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "api_key", value: "secret"),
                HAR.QueryParameter(name: "page", value: "1"),
                HAR.QueryParameter(name: "limit", value: "10"),
            ])

            let filter = Filter.queryParameters(keeping: ["page", "limit"])
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString.map(\.name) == ["page", "limit"])
        }

        @Test("queryParameters(keeping:) is case-sensitive for parameter names")
        func queryParametersKeepingCaseSensitive() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "API_KEY", value: "value1"),
                HAR.QueryParameter(name: "api_key", value: "value2"),
            ])

            let filter = Filter.queryParameters(keeping: ["api_key"])
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString.map(\.name) == ["api_key"])
            #expect(result.request.queryString.first?.value == "value2")
        }
    }

    // MARK: - Body Filter Tests

    @Suite("Filter.body Tests")
    struct BodyFilterTests {
        @Test("replaces pattern in request body")
        func replacesPatternInRequestBody() async {
            let entry = makeEntryWithBody(
                requestBody: "{\"password\":\"secret123\",\"user\":\"test\"}",
                responseBody: nil
            )

            let filter = Filter.body(pattern: "secret123", replacement: "[REDACTED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.postData?.text == "{\"password\":\"[REDACTED]\",\"user\":\"test\"}")
        }

        @Test("replaces pattern in response body")
        func replacesPatternInResponseBody() async {
            let entry = makeEntryWithBody(
                requestBody: nil,
                responseBody: "{\"token\":\"eyJhbGciOiJIUzI1NiJ9\",\"status\":\"ok\"}"
            )

            let filter = Filter.body(pattern: "eyJhbGciOiJIUzI1NiJ9", replacement: "[TOKEN]")
            let result = await filter.apply(to: entry)

            #expect(result.response.content.text == "{\"token\":\"[TOKEN]\",\"status\":\"ok\"}")
        }

        @Test("replaces pattern in both request and response bodies")
        func replacesPatternInBothBodies() async {
            let entry = makeEntryWithBody(
                requestBody: "API_KEY=secret",
                responseBody: "Your API_KEY is valid"
            )

            let filter = Filter.body(pattern: "API_KEY", replacement: "KEY")
            let result = await filter.apply(to: entry)

            #expect(result.request.postData?.text == "KEY=secret")
            #expect(result.response.content.text == "Your KEY is valid")
        }

        @Test("replaces all occurrences of pattern")
        func replacesAllOccurrences() async {
            let entry = makeEntryWithBody(
                requestBody: "secret-secret-secret",
                responseBody: nil
            )

            let filter = Filter.body(pattern: "secret", replacement: "hidden")
            let result = await filter.apply(to: entry)

            #expect(result.request.postData?.text == "hidden-hidden-hidden")
        }

        @Test("preserves postData properties")
        func preservesPostDataProperties() async {
            let entry = makeEntryWithPostData(
                mimeType: "application/json",
                text: "secret-data",
                params: [HAR.PostData.Param(name: "field", value: "value")],
                comment: "Request body"
            )

            let filter = Filter.body(pattern: "secret", replacement: "hidden")
            let result = await filter.apply(to: entry)

            #expect(result.request.postData?.mimeType == "application/json")
            #expect(result.request.postData?.text == "hidden-data")
            #expect(result.request.postData?.params?.count == 1)
            #expect(result.request.postData?.comment == "Request body")
        }

        @Test("preserves response content properties")
        func preservesResponseContentProperties() async {
            let entry = makeEntryWithResponseContent(
                size: 100,
                mimeType: "application/json",
                text: "secret-response",
                encoding: nil,
                compression: 50,
                comment: "Response content"
            )

            let filter = Filter.body(pattern: "secret", replacement: "hidden")
            let result = await filter.apply(to: entry)

            #expect(result.response.content.size == 100)
            #expect(result.response.content.mimeType == "application/json")
            #expect(result.response.content.text == "hidden-response")
            #expect(result.response.content.compression == 50)
            #expect(result.response.content.comment == "Response content")
        }

        @Test("handles nil request body")
        func handlesNilRequestBody() async {
            let entry = makeEntryWithBody(requestBody: nil, responseBody: "response")

            let filter = Filter.body(pattern: "secret", replacement: "hidden")
            let result = await filter.apply(to: entry)

            #expect(result.request.postData == nil)
            #expect(result.response.content.text == "response")
        }

        @Test("handles nil response body")
        func handlesNilResponseBody() async {
            let entry = makeEntryWithBody(requestBody: "request secret", responseBody: nil)

            let filter = Filter.body(pattern: "secret", replacement: "hidden")
            let result = await filter.apply(to: entry)

            #expect(result.request.postData?.text == "request hidden")
            #expect(result.response.content.text == nil)
        }
    }

    // MARK: - Custom Filter Tests

    @Suite("Filter.custom Tests")
    struct CustomFilterTests {
        @Test("applies arbitrary transformation")
        func appliesArbitraryTransformation() async {
            let entry = makeTestEntry()

            let filter = Filter.custom { entry in
                var modified = entry
                modified.comment = "Modified by custom filter"
                return modified
            }

            let result = await filter.apply(to: entry)

            #expect(result.comment == "Modified by custom filter")
        }

        @Test("can modify request")
        func canModifyRequest() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [HAR.Header(name: "Custom", value: "original")],
                responseHeaders: []
            )

            let filter = Filter.custom { entry in
                var modified = entry
                modified.request.headers = entry.request.headers.map { header in
                    HAR.Header(name: header.name, value: header.value.uppercased())
                }
                return modified
            }

            let result = await filter.apply(to: entry)

            #expect(result.request.headers[0].value == "ORIGINAL")
        }

        @Test("can modify response")
        func canModifyResponse() async {
            let entry = makeTestEntry()

            let filter = Filter.custom { entry in
                var modified = entry
                modified.response.status = 201
                modified.response.statusText = "Created"
                return modified
            }

            let result = await filter.apply(to: entry)

            #expect(result.response.status == 201)
            #expect(result.response.statusText == "Created")
        }

        @Test("supports async operations")
        func supportsAsyncOperations() async {
            let entry = makeTestEntry()

            let filter = Filter.custom { entry in
                await Task.yield()
                var modified = entry
                modified.comment = "Async modification"
                return modified
            }

            let result = await filter.apply(to: entry)

            #expect(result.comment == "Async modification")
        }
    }

    // MARK: - Convenience Extension Tests

    @Suite("Filter Convenience Extensions Tests")
    struct ConvenienceExtensionTests {
        @Test("headers variadic convenience method")
        func headersVariadic() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [
                    HAR.Header(name: "Authorization", value: "secret"),
                    HAR.Header(name: "X-API-Key", value: "key123"),
                ],
                responseHeaders: []
            )

            let filter = Filter.headers("Authorization", "X-API-Key")
            let result = await filter.apply(to: entry)

            #expect(result.request.headers[0].value == "[FILTERED]")
            #expect(result.request.headers[1].value == "[FILTERED]")
        }

        @Test("headers variadic with custom replacement")
        func headersVariadicWithReplacement() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [HAR.Header(name: "Authorization", value: "secret")],
                responseHeaders: []
            )

            let filter = Filter.headers("Authorization", replacement: "***")
            let result = await filter.apply(to: entry)

            #expect(result.request.headers[0].value == "***")
        }

        @Test("headers removing array method")
        func headersRemovingArray() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [
                    HAR.Header(name: "Auth", value: "secret1"),
                    HAR.Header(name: "Token", value: "secret2"),
                ],
                responseHeaders: []
            )

            let filter = Filter.headers(removing: ["Auth", "Token"], replacement: "[HIDDEN]")
            let result = await filter.apply(to: entry)

            #expect(result.request.headers[0].value == "[HIDDEN]")
            #expect(result.request.headers[1].value == "[HIDDEN]")
        }

        @Test("headers removing uses default replacement")
        func headersRemovingDefaultReplacement() async {
            let entry = makeEntryWithHeaders(
                requestHeaders: [HAR.Header(name: "Authorization", value: "secret")],
                responseHeaders: []
            )

            let filter = Filter.headers(removing: ["Authorization"])
            let result = await filter.apply(to: entry)

            #expect(result.request.headers[0].value == "[FILTERED]")
        }

        @Test("queryParameters variadic convenience method")
        func queryParametersVariadic() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "api_key", value: "secret"),
                HAR.QueryParameter(name: "token", value: "abc123"),
            ])

            let filter = Filter.queryParameters("api_key", "token")
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString[0].value == "[FILTERED]")
            #expect(result.request.queryString[1].value == "[FILTERED]")
        }

        @Test("queryParameters variadic with custom replacement")
        func queryParametersVariadicWithReplacement() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "secret", value: "value")
            ])

            let filter = Filter.queryParameters("secret", replacement: "***")
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString[0].value == "***")
        }

        @Test("queryParameters removing array method")
        func queryParametersRemovingArray() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "key1", value: "value1"),
                HAR.QueryParameter(name: "key2", value: "value2"),
            ])

            let filter = Filter.queryParameters(removing: ["key1", "key2"], replacement: "[REMOVED]")
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString[0].value == "[REMOVED]")
            #expect(result.request.queryString[1].value == "[REMOVED]")
        }

        @Test("queryParameters removing uses default replacement")
        func queryParametersRemovingDefaultReplacement() async {
            let entry = makeEntryWithQueryParameters([
                HAR.QueryParameter(name: "secret", value: "value")
            ])

            let filter = Filter.queryParameters(removing: ["secret"])
            let result = await filter.apply(to: entry)

            #expect(result.request.queryString[0].value == "[FILTERED]")
        }

        @Test("body replacing convenience method")
        func bodyReplacing() async {
            let entry = makeEntryWithBody(
                requestBody: "password=secret123",
                responseBody: nil
            )

            let filter = Filter.body(replacing: "secret123", with: "[HIDDEN]")
            let result = await filter.apply(to: entry)

            #expect(result.request.postData?.text == "password=[HIDDEN]")
        }

        @Test("body replacing uses default replacement")
        func bodyReplacingDefaultReplacement() async {
            let entry = makeEntryWithBody(
                requestBody: "token=abc123",
                responseBody: nil
            )

            let filter = Filter.body(replacing: "abc123")
            let result = await filter.apply(to: entry)

            #expect(result.request.postData?.text == "token=[FILTERED]")
        }
    }

    // MARK: - Body Transform Tests

    @Suite("Filter.body(transforming:) Tests")
    struct BodyTransformTests {
        struct User: Codable, Equatable {
            var name: String
            var role: String
        }

        @Test("transforms request body")
        func transformsRequestBody() async {
            let entry = makeEntryWithBody(
                requestBody: #"{"name":"Alice","role":"admin"}"#,
                responseBody: nil
            )

            let filter = Filter.body(decoding: User.self) { user in
                var modified = user
                modified.role = "user"
                return modified
            }

            let result = await filter.apply(to: entry)

            // Expected format matches JSONEncoder output formatting: .prettyPrinted, .sortedKeys
            let expected = """
                {
                  "name" : "Alice",
                  "role" : "user"
                }
                """

            #expect(result.request.postData?.text == expected)
        }

        @Test("transforms response body")
        func transformsResponseBody() async {
            let entry = makeEntryWithBody(
                requestBody: nil,
                responseBody: #"{"name":"Bob","role":"guest"}"#
            )

            let filter = Filter.body(decoding: User.self) { user in
                var modified = user
                modified.name = "Robert"
                return modified
            }

            let result = await filter.apply(to: entry)

            let expected = """
                {
                  "name" : "Robert",
                  "role" : "guest"
                }
                """

            #expect(result.response.content.text == expected)
        }

        @Test("ignores non-matching types")
        func ignoresNonMatchingTypes() async {
            let entry = makeEntryWithBody(
                requestBody: #"{"foo":"bar"}"#,  // Not a User
                responseBody: nil
            )

            let filter = Filter.body(decoding: User.self) { user in
                var modified = user
                modified.name = "Modified"
                return modified
            }

            let result = await filter.apply(to: entry)

            #expect(result.request.postData?.text == #"{"foo":"bar"}"#)
        }

        @Test("handles base64 encoded content")
        func handlesBase64EncodedContent() async {
            let jsonData = #"{"name":"Alice","role":"admin"}"#.data(using: .utf8)!
            let base64Text = jsonData.base64EncodedString()

            let entry = makeEntryWithResponseContent(
                size: jsonData.count,
                mimeType: "application/json",
                text: base64Text,
                encoding: "base64",
                compression: nil,
                comment: nil
            )

            let filter = Filter.body(decoding: User.self) { user in
                var modified = user
                modified.role = "user"
                return modified
            }

            let result = await filter.apply(to: entry)

            // Should decode base64, transform, and potentially re-encode
            #expect(result.response.content.text != nil)
        }

        @Test("handles invalid base64 gracefully")
        func handlesInvalidBase64Gracefully() async {
            let entry = makeEntryWithResponseContent(
                size: 10,
                mimeType: "application/json",
                text: "invalid-base64!!!",
                encoding: "base64",
                compression: nil,
                comment: nil
            )

            let filter = Filter.body(decoding: User.self) { user in
                var modified = user
                modified.name = "Modified"
                return modified
            }

            let result = await filter.apply(to: entry)

            // Should leave content unchanged if base64 decode fails
            #expect(result.response.content.text == "invalid-base64!!!")
        }

        @Test("handles non-JSON content gracefully")
        func handlesNonJSONContentGracefully() async {
            let entry = makeEntryWithBody(
                requestBody: "plain text, not JSON",
                responseBody: nil
            )

            let filter = Filter.body(decoding: User.self) { user in
                var modified = user
                modified.name = "Modified"
                return modified
            }

            let result = await filter.apply(to: entry)

            // Should leave content unchanged if JSON decode fails
            #expect(result.request.postData?.text == "plain text, not JSON")
        }
    }
}

// MARK: - Test Helpers

private func makeTestEntry() -> HAR.Entry {
    let request = HAR.Request(
        method: "GET",
        url: "https://example.com/api",
        httpVersion: "HTTP/1.1",
        headers: [],
        bodySize: 0
    )
    let content = HAR.Content(size: 2, mimeType: "text/plain", text: "OK")
    let response = HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: 2
    )
    return HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: request,
        response: response,
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}

private func makeEntryWithHeaders(
    requestHeaders: [HAR.Header],
    responseHeaders: [HAR.Header]
) -> HAR.Entry {
    let request = HAR.Request(
        method: "GET",
        url: "https://example.com/api",
        httpVersion: "HTTP/1.1",
        headers: requestHeaders,
        bodySize: 0
    )
    let content = HAR.Content(size: 2, mimeType: "text/plain", text: "OK")
    let response = HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: responseHeaders,
        content: content,
        bodySize: 2
    )
    return HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: request,
        response: response,
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}

private func makeEntryWithQueryParameters(_ queryString: [HAR.QueryParameter]) -> HAR.Entry {
    let request = HAR.Request(
        method: "GET",
        url: "https://example.com/api",
        httpVersion: "HTTP/1.1",
        headers: [],
        queryString: queryString,
        bodySize: 0
    )
    let content = HAR.Content(size: 2, mimeType: "text/plain", text: "OK")
    let response = HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: 2
    )
    return HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: request,
        response: response,
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}

private func makeEntryWithBody(requestBody: String?, responseBody: String?) -> HAR.Entry {
    let postData: HAR.PostData? = requestBody.map {
        HAR.PostData(mimeType: "text/plain", text: $0)
    }
    let request = HAR.Request(
        method: "POST",
        url: "https://example.com/api",
        httpVersion: "HTTP/1.1",
        headers: [],
        postData: postData,
        bodySize: requestBody?.count ?? 0
    )
    let content = HAR.Content(
        size: responseBody?.count ?? 0,
        mimeType: "text/plain",
        text: responseBody
    )
    let response = HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: responseBody?.count ?? 0
    )
    return HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: request,
        response: response,
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}

private func makeEntryWithPostData(
    mimeType: String,
    text: String?,
    params: [HAR.PostData.Param]?,
    comment: String?
) -> HAR.Entry {
    let postData = HAR.PostData(
        mimeType: mimeType,
        params: params,
        text: text,
        comment: comment
    )
    let request = HAR.Request(
        method: "POST",
        url: "https://example.com/api",
        httpVersion: "HTTP/1.1",
        headers: [],
        postData: postData,
        bodySize: text?.count ?? 0
    )
    let content = HAR.Content(size: 0, mimeType: "text/plain")
    let response = HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: 0
    )
    return HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: request,
        response: response,
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}

private func makeEntryWithResponseContent(
    size: Int,
    mimeType: String,
    text: String?,
    encoding: String?,
    compression: Int?,
    comment: String?
) -> HAR.Entry {
    let request = HAR.Request(
        method: "GET",
        url: "https://example.com/api",
        httpVersion: "HTTP/1.1",
        headers: [],
        bodySize: 0
    )
    let content = HAR.Content(
        size: size,
        compression: compression,
        mimeType: mimeType,
        text: text,
        encoding: encoding,
        comment: comment
    )
    let response = HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: size
    )
    return HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: request,
        response: response,
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}
