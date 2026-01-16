import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

// MARK: - Log Tests

@Suite("HAR Tests")
struct HARTests {

    @Suite("HAR.Log Tests")
    struct LogTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let creator = HAR.Creator(name: "Test", version: "1.0")
            let log = HAR.Log(version: "1.2", creator: creator)

            #expect(log.version == "1.2")
            #expect(log.creator.name == "Test")
            #expect(log.creator.version == "1.0")
            #expect(log.browser == nil)
            #expect(log.pages == nil)
            #expect(log.entries.isEmpty)
            #expect(log.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let creator = HAR.Creator(name: "Creator", version: "1.0")
            let browser = HAR.Browser(name: "Safari", version: "17.0")
            let page = HAR.Page(
                startedDateTime: Date(),
                id: "page_0",
                title: "Test Page",
                pageTimings: HAR.Page.PageTimings()
            )
            let entry = makeTestEntry()

            let log = HAR.Log(
                version: "1.2",
                creator: creator,
                browser: browser,
                pages: [page],
                entries: [entry],
                comment: "Test comment"
            )

            #expect(log.version == "1.2")
            #expect(log.creator.name == "Creator")
            #expect(log.browser?.name == "Safari")
            #expect(log.pages?.count == 1)
            #expect(log.entries.count == 1)
            #expect(log.comment == "Test comment")
        }

        @Test("encodes and decodes correctly")
        func codable() throws {
            let creator = HAR.Creator(name: "Test", version: "1.0", comment: "Creator comment")
            let log = HAR.Log(version: "1.2", creator: creator, comment: "Log comment")

            let encoder = JSONEncoder()
            let data = try encoder.encode(log)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(HAR.Log.self, from: data)

            #expect(decoded.version == log.version)
            #expect(decoded.creator.name == log.creator.name)
            #expect(decoded.creator.comment == "Creator comment")
            #expect(decoded.comment == "Log comment")
        }
    }

    // MARK: - Creator Tests

    @Suite("HAR.Creator Tests")
    struct CreatorTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let creator = HAR.Creator(name: "MyApp", version: "2.0")

            #expect(creator.name == "MyApp")
            #expect(creator.version == "2.0")
            #expect(creator.comment == nil)
        }

        @Test("initializes with comment")
        func initWithComment() {
            let creator = HAR.Creator(name: "MyApp", version: "2.0", comment: "Test comment")

            #expect(creator.name == "MyApp")
            #expect(creator.version == "2.0")
            #expect(creator.comment == "Test comment")
        }

        @Test("Browser is typealias for Creator")
        func browserTypealias() {
            let browser: HAR.Browser = HAR.Creator(name: "Firefox", version: "120.0")

            #expect(browser.name == "Firefox")
            #expect(browser.version == "120.0")
        }
    }

    // MARK: - Page Tests

    @Suite("HAR.Page Tests")
    struct PageTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let date = Date()
            let timings = HAR.Page.PageTimings()
            let page = HAR.Page(
                startedDateTime: date,
                id: "page_1",
                title: "Home Page",
                pageTimings: timings
            )

            #expect(page.startedDateTime == date)
            #expect(page.id == "page_1")
            #expect(page.title == "Home Page")
            #expect(page.comment == nil)
        }

        @Test("initializes with comment")
        func initWithComment() {
            let page = HAR.Page(
                startedDateTime: Date(),
                id: "page_1",
                title: "Home Page",
                pageTimings: HAR.Page.PageTimings(),
                comment: "Main page"
            )

            #expect(page.comment == "Main page")
        }
    }

    // MARK: - PageTimings Tests

    @Suite("HAR.Page.PageTimings Tests")
    struct PageTimingsTests {
        @Test("initializes with default nil values")
        func initWithDefaults() {
            let timings = HAR.Page.PageTimings()

            #expect(timings.onContentLoad == nil)
            #expect(timings.onLoad == nil)
            #expect(timings.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let timings = HAR.Page.PageTimings(
                onContentLoad: 1500,
                onLoad: 2500,
                comment: "Fast load"
            )

            #expect(timings.onContentLoad == 1500)
            #expect(timings.onLoad == 2500)
            #expect(timings.comment == "Fast load")
        }

        @Test("accepts -1 for unavailable timings")
        func unavailableTimings() {
            let timings = HAR.Page.PageTimings(onContentLoad: -1, onLoad: -1)

            #expect(timings.onContentLoad == -1)
            #expect(timings.onLoad == -1)
        }
    }

    // MARK: - Entry Tests

    @Suite("HAR.Entry Tests")
    struct EntryTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let entry = makeTestEntry()

            #expect(entry.time == 100)
            #expect(entry.request.method == "GET")
            #expect(entry.response.status == 200)
            #expect(entry.cache == nil)
            #expect(entry.serverIPAddress == nil)
            #expect(entry.connection == nil)
            #expect(entry.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let date = Date()
            let request = makeTestRequest()
            let response = makeTestResponse()
            let cache = HAR.Cache()
            let timings = HAR.Timings(send: 10, wait: 50, receive: 20)

            let entry = HAR.Entry(
                startedDateTime: date,
                time: 100,
                request: request,
                response: response,
                cache: cache,
                timings: timings,
                serverIPAddress: "192.168.1.1",
                connection: "443",
                comment: "API call"
            )

            #expect(entry.startedDateTime == date)
            #expect(entry.time == 100)
            #expect(entry.cache != nil)
            #expect(entry.serverIPAddress == "192.168.1.1")
            #expect(entry.connection == "443")
            #expect(entry.comment == "API call")
        }

        @Test("converts to URLResponse")
        func toURLResponse() throws {
            let entry = makeTestEntry()
            let (response, data) = try entry.toURLResponse()

            #expect(response.statusCode == 200)
            #expect(String(data: data, encoding: .utf8) == "OK")
        }

        @Test("converts base64 encoded content to URLResponse")
        func toURLResponseBase64() throws {
            let request = makeTestRequest()
            let binaryData = Data([0x00, 0x01, 0x02, 0x03])
            let content = HAR.Content(
                size: binaryData.count,
                mimeType: "application/octet-stream",
                text: binaryData.base64EncodedString(),
                encoding: "base64"
            )
            let response = HAR.Response(
                status: 200,
                statusText: "OK",
                httpVersion: "HTTP/1.1",
                headers: [],
                content: content,
                bodySize: binaryData.count
            )
            let entry = HAR.Entry(
                startedDateTime: Date(),
                time: 100,
                request: request,
                response: response,
                timings: HAR.Timings(send: 0, wait: 100, receive: 0)
            )

            let (_, data) = try entry.toURLResponse()

            #expect(data == binaryData)
        }

        @Test("toURLResponse throws for truly invalid URL")
        func toURLResponseThrowsForInvalidURL() {
            // Use a URL that URL(string:) will accept but HTTPURLResponse cannot create
            // Actually, URL(string:) percent-encodes most strings, so we need to test with
            // a URL that creates a response but fails validation
            // Since URL(string:) handles most cases, we'll test with an empty string which fails
            let request = HAR.Request(
                method: "GET",
                url: "",
                httpVersion: "HTTP/1.1",
                headers: [],
                bodySize: 0
            )
            let response = makeTestResponse()
            let entry = HAR.Entry(
                startedDateTime: Date(),
                time: 100,
                request: request,
                response: response,
                timings: HAR.Timings(send: 0, wait: 100, receive: 0)
            )

            #expect(throws: ReplayError.self) {
                try entry.toURLResponse()
            }
        }

        @Test("toURLResponse throws for invalid base64")
        func toURLResponseThrowsForInvalidBase64() {
            let request = makeTestRequest()
            let content = HAR.Content(
                size: 10,
                mimeType: "application/octet-stream",
                text: "invalid-base64!!!",
                encoding: "base64"
            )
            let response = HAR.Response(
                status: 200,
                statusText: "OK",
                httpVersion: "HTTP/1.1",
                headers: [],
                content: content,
                bodySize: 10
            )
            let entry = HAR.Entry(
                startedDateTime: Date(),
                time: 100,
                request: request,
                response: response,
                timings: HAR.Timings(send: 0, wait: 100, receive: 0)
            )

            #expect(throws: ReplayError.self) {
                try entry.toURLResponse()
            }
        }

        @Test("toURLResponse handles empty body")
        func toURLResponseHandlesEmptyBody() throws {
            let request = makeTestRequest()
            let content = HAR.Content(
                size: 0,
                mimeType: "text/plain",
                text: nil
            )
            let response = HAR.Response(
                status: 204,
                statusText: "No Content",
                httpVersion: "HTTP/1.1",
                headers: [],
                content: content,
                bodySize: 0
            )
            let entry = HAR.Entry(
                startedDateTime: Date(),
                time: 100,
                request: request,
                response: response,
                timings: HAR.Timings(send: 0, wait: 100, receive: 0)
            )

            let (_, data) = try entry.toURLResponse()

            #expect(data.isEmpty)
        }

        @Test("toURLResponse handles UTF-8 text without encoding")
        func toURLResponseHandlesUTF8Text() throws {
            let request = makeTestRequest()
            let content = HAR.Content(
                size: 11,
                mimeType: "text/plain",
                text: "Hello World",
                encoding: nil
            )
            let response = HAR.Response(
                status: 200,
                statusText: "OK",
                httpVersion: "HTTP/1.1",
                headers: [],
                content: content,
                bodySize: 11
            )
            let entry = HAR.Entry(
                startedDateTime: Date(),
                time: 100,
                request: request,
                response: response,
                timings: HAR.Timings(send: 0, wait: 100, receive: 0)
            )

            let (_, data) = try entry.toURLResponse()

            #expect(String(data: data, encoding: .utf8) == "Hello World")
        }
    }

    // MARK: - Request Tests

    @Suite("HAR.Request Tests")
    struct RequestTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let request = HAR.Request(
                method: "POST",
                url: "https://api.example.com/data",
                httpVersion: "HTTP/2",
                headers: [HAR.Header(name: "Content-Type", value: "application/json")],
                bodySize: 42
            )

            #expect(request.method == "POST")
            #expect(request.url == "https://api.example.com/data")
            #expect(request.httpVersion == "HTTP/2")
            #expect(request.cookies.isEmpty)
            #expect(request.headers.count == 1)
            #expect(request.queryString.isEmpty)
            #expect(request.postData == nil)
            #expect(request.headersSize == -1)
            #expect(request.bodySize == 42)
            #expect(request.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let cookies = [HAR.Cookie(name: "session", value: "abc123")]
            let headers = [HAR.Header(name: "Accept", value: "application/json")]
            let queryString = [HAR.QueryParameter(name: "page", value: "1")]
            let postData = HAR.PostData(mimeType: "application/json", text: "{}")

            let request = HAR.Request(
                method: "POST",
                url: "https://api.example.com/data",
                httpVersion: "HTTP/1.1",
                cookies: cookies,
                headers: headers,
                queryString: queryString,
                postData: postData,
                headersSize: 150,
                bodySize: 2,
                comment: "Create resource"
            )

            #expect(request.cookies.count == 1)
            #expect(request.cookies[0].name == "session")
            #expect(request.queryString.count == 1)
            #expect(request.queryString[0].name == "page")
            #expect(request.postData?.mimeType == "application/json")
            #expect(request.headersSize == 150)
            #expect(request.comment == "Create resource")
        }

        @Test("creates from URLRequest")
        func initFromURLRequest() throws {
            var urlRequest = URLRequest(url: URL(string: "https://example.com/api?foo=bar")!)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = "{\"key\":\"value\"}".data(using: .utf8)

            let request = try HAR.Request(from: urlRequest)

            #expect(request.method == "POST")
            #expect(request.url == "https://example.com/api?foo=bar")
            #expect(request.httpVersion == "HTTP/1.1")
            #expect(request.queryString.count == 1)
            #expect(request.queryString[0].name == "foo")
            #expect(request.queryString[0].value == "bar")
            #expect(request.postData?.mimeType == "application/json")
            #expect(request.postData?.text == "{\"key\":\"value\"}")
            #expect(request.bodySize == 15)
        }

        @Test("throws for URLRequest without URL")
        func initFromURLRequestWithoutURL() {
            let urlRequest = URLRequest(url: URL(string: "about:blank")!)
            var mutableRequest = urlRequest
            mutableRequest.url = nil

            #expect(throws: ReplayError.self) {
                try HAR.Request(from: mutableRequest)
            }
        }

        @Test("parses cookies from Cookie header")
        func parseCookiesFromHeader() throws {
            var urlRequest = URLRequest(url: URL(string: "https://example.com")!)
            urlRequest.setValue("session=abc123; user=john", forHTTPHeaderField: "Cookie")

            let request = try HAR.Request(from: urlRequest)

            #expect(request.cookies.count == 2)
            #expect(request.cookies[0].name == "session")
            #expect(request.cookies[0].value == "abc123")
            #expect(request.cookies[1].name == "user")
            #expect(request.cookies[1].value == "john")
        }

        @Test("handles cookie values with equals signs")
        func parseCookiesWithEqualsInValue() throws {
            var urlRequest = URLRequest(url: URL(string: "https://example.com")!)
            urlRequest.setValue("token=abc=def=ghi", forHTTPHeaderField: "Cookie")

            let request = try HAR.Request(from: urlRequest)

            #expect(request.cookies.count == 1)
            #expect(request.cookies[0].name == "token")
            #expect(request.cookies[0].value == "abc=def=ghi")
        }

        @Test("handles empty Cookie header")
        func parseCookiesEmptyHeader() throws {
            var urlRequest = URLRequest(url: URL(string: "https://example.com")!)
            urlRequest.setValue("", forHTTPHeaderField: "Cookie")

            let request = try HAR.Request(from: urlRequest)

            #expect(request.cookies.isEmpty)
        }

        @Test("skips malformed cookie entries")
        func parseCookiesSkipsMalformed() throws {
            var urlRequest = URLRequest(url: URL(string: "https://example.com")!)
            urlRequest.setValue("valid=value; malformed; another=ok", forHTTPHeaderField: "Cookie")

            let request = try HAR.Request(from: urlRequest)

            #expect(request.cookies.count == 2)
            #expect(request.cookies[0].name == "valid")
            #expect(request.cookies[1].name == "another")
        }

        @Test("handles non-UTF8 body as base64")
        func handlesNonUTF8BodyAsBase64() throws {
            var urlRequest = URLRequest(url: URL(string: "https://example.com/api")!)
            urlRequest.httpMethod = "POST"
            // Create binary data that's not valid UTF-8
            let binaryData = Data([0xFF, 0xFE, 0xFD, 0xFC])
            urlRequest.httpBody = binaryData
            urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

            let request = try HAR.Request(from: urlRequest)

            #expect(request.postData?.text == binaryData.base64EncodedString())
            #expect(request.bodySize == binaryData.count)
        }

        @Test("handles request without httpMethod")
        func handlesRequestWithoutHTTPMethod() throws {
            var urlRequest = URLRequest(url: URL(string: "https://example.com/api")!)
            urlRequest.httpMethod = nil

            let request = try HAR.Request(from: urlRequest)

            #expect(request.method == "GET")
        }

        @Test("handles request with query parameters in URL")
        func handlesRequestWithQueryParameters() throws {
            let urlRequest = URLRequest(url: URL(string: "https://example.com/api?foo=bar&baz=qux")!)

            let request = try HAR.Request(from: urlRequest)

            #expect(request.queryString.count == 2)
            #expect(request.queryString.contains { $0.name == "foo" && $0.value == "bar" })
            #expect(request.queryString.contains { $0.name == "baz" && $0.value == "qux" })
        }

        @Test("handles request with nil query item values")
        func handlesRequestWithNilQueryValues() throws {
            let urlRequest = URLRequest(url: URL(string: "https://example.com/api?key")!)

            let request = try HAR.Request(from: urlRequest)

            #expect(request.queryString.count == 1)
            #expect(request.queryString[0].name == "key")
            #expect(request.queryString[0].value == "")
        }

        @Test("headers order is deterministic across multiple conversions")
        func headersOrderIsDeterministic() throws {
            // Create a URLRequest with multiple headers
            // Using enough headers to make nondeterministic ordering likely to be observable
            // This did reliably produce failures before adding the explicit sorting
            var urlRequest = URLRequest(url: URL(string: "https://example.com/api")!)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
            urlRequest.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            urlRequest.setValue("Bearer token123", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("keep-alive", forHTTPHeaderField: "Connection")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("example.com", forHTTPHeaderField: "Host")
            urlRequest.setValue("https://example.com", forHTTPHeaderField: "Origin")
            urlRequest.setValue("https://example.com/previous", forHTTPHeaderField: "Referer")
            urlRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            // Convert to HAR.Request multiple times
            let iterations = 10
            var headerOrders: [[String]] = []
            
            for _ in 0..<iterations {
                let request = try HAR.Request(from: urlRequest)
                let headerNames = request.headers.map { $0.name }
                headerOrders.append(headerNames)
            }

            // Check if all iterations produced the same header order
            let firstOrder = headerOrders[0]
            let allSame = headerOrders.allSatisfy { $0 == firstOrder }
            #expect(allSame, "Header order should be consistent across multiple conversions, but got varying orders: \(headerOrders)")
        }
    }

    // MARK: - Response Tests

    @Suite("HAR.Response Tests")
    struct ResponseTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let content = HAR.Content(size: 100, mimeType: "text/html")
            let response = HAR.Response(
                status: 404,
                statusText: "Not Found",
                httpVersion: "HTTP/1.1",
                headers: [],
                content: content,
                bodySize: 100
            )

            #expect(response.status == 404)
            #expect(response.statusText == "Not Found")
            #expect(response.httpVersion == "HTTP/1.1")
            #expect(response.cookies.isEmpty)
            #expect(response.headers.isEmpty)
            #expect(response.content.size == 100)
            #expect(response.redirectURL == "")
            #expect(response.headersSize == -1)
            #expect(response.bodySize == 100)
            #expect(response.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let cookies = [HAR.Cookie(name: "token", value: "xyz")]
            let headers = [HAR.Header(name: "Content-Type", value: "text/html")]
            let content = HAR.Content(size: 1024, mimeType: "text/html", text: "<html></html>")

            let response = HAR.Response(
                status: 301,
                statusText: "Moved Permanently",
                httpVersion: "HTTP/1.1",
                cookies: cookies,
                headers: headers,
                content: content,
                redirectURL: "https://example.com/new-location",
                headersSize: 200,
                bodySize: 1024,
                comment: "Redirect"
            )

            #expect(response.status == 301)
            #expect(response.cookies.count == 1)
            #expect(response.redirectURL == "https://example.com/new-location")
            #expect(response.headersSize == 200)
            #expect(response.comment == "Redirect")
        }

        @Test("creates from HTTPURLResponse")
        func initFromHTTPURLResponse() throws {
            let url = URL(string: "https://example.com")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = "{\"success\":true}".data(using: .utf8)!

            let response = try HAR.Response(from: httpResponse, data: data)

            #expect(response.status == 200)
            #expect(response.httpVersion == "HTTP/1.1")
            #expect(response.content.text == "{\"success\":true}")
            #expect(response.content.encoding == nil)
            #expect(response.bodySize == data.count)
        }

        @Test("headers order is deterministic across multiple conversions")
        func headersOrderIsDeterministic() throws {
            // Create an HTTPURLResponse with multiple headers
            // Using enough headers to make nondeterministic ordering likely to be observable
            // This did reliably produce failures before adding the explicit sorting
            let url = URL(string: "https://example.com/api")!
            let data = "{\"test\":true}".data(using: .utf8)!

            // Convert to HAR.Response multiple times
            let iterations = 10
            var headerOrders: [[String]] = []
            
            for _ in 0..<iterations {
                let httpResponse = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "application/json",
                        "Cache-Control": "no-cache, no-store, must-revalidate",
                        "Content-Length": "12345",
                        "Date": "Thu, 16 Jan 2026 12:00:00 GMT",
                        "ETag": "\"abc123\"",
                        "Expires": "0",
                        "Last-Modified": "Thu, 16 Jan 2026 11:00:00 GMT",
                        "Server": "nginx/1.21.0",
                        "Vary": "Accept-Encoding",
                        "X-Frame-Options": "SAMEORIGIN"
                    ]
                )!
                
                let response = try HAR.Response(from: httpResponse, data: data)
                let headerNames = response.headers.map { $0.name }
                headerOrders.append(headerNames)
            }

            // Check if all iterations produced the same header order
            let firstOrder = headerOrders[0]
            let allSame = headerOrders.allSatisfy { $0 == firstOrder }
            #expect(allSame, "Header order should be consistent across multiple conversions, but got varying orders: \(headerOrders)")
        }

        @Test("encodes binary data as base64")
        func initFromHTTPURLResponseBinary() throws {
            let url = URL(string: "https://example.com/image.png")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
            )!
            let binaryData = Data([0xFF, 0xD8, 0xFF, 0xE0])

            let response = try HAR.Response(from: httpResponse, data: binaryData)

            #expect(response.content.encoding == "base64")
            #expect(response.content.text == binaryData.base64EncodedString())
        }

        @Test("parses cookies from Set-Cookie header")
        func parseCookiesFromSetCookieHeader() throws {
            let url = URL(string: "https://example.com")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Set-Cookie": "session=abc123; Path=/; HttpOnly"
                ]
            )!

            let response = try HAR.Response(from: httpResponse, data: Data())

            #expect(response.cookies.count == 1)
            #expect(response.cookies[0].name == "session")
            #expect(response.cookies[0].value == "abc123")
            #expect(response.cookies[0].path == "/")
            #expect(response.cookies[0].httpOnly == true)
        }

        @Test("parses secure cookie attributes")
        func parsesSecureCookieAttributes() throws {
            let url = URL(string: "https://example.com")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Set-Cookie": "token=xyz; Secure; HttpOnly; Path=/api"
                ]
            )!

            let response = try HAR.Response(from: httpResponse, data: Data())

            #expect(response.cookies.count == 1)
            #expect(response.cookies[0].name == "token")
            #expect(response.cookies[0].secure == true)
            #expect(response.cookies[0].httpOnly == true)
            #expect(response.cookies[0].path == "/api")
        }

        @Test("parses cookie domain")
        func parsesCookieDomain() throws {
            let url = URL(string: "https://example.com")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Set-Cookie": "user=john; Domain=.example.com; Path=/"
                ]
            )!

            let response = try HAR.Response(from: httpResponse, data: Data())

            #expect(response.cookies.count == 1)
            #expect(response.cookies[0].domain == ".example.com")
        }

        @Test("handles response without cookies")
        func handlesResponseWithoutCookies() throws {
            let url = URL(string: "https://example.com")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!

            let response = try HAR.Response(from: httpResponse, data: Data())

            #expect(response.cookies.isEmpty)
        }

        @Test("handles response with empty URL")
        func handlesResponseWithEmptyURL() throws {
            // HTTPURLResponse requires a URL, so we'll test with a valid URL but check cookie handling
            let url = URL(string: "https://example.com")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!

            let response = try HAR.Response(from: httpResponse, data: Data())

            #expect(response.cookies.isEmpty)
        }

        @Test("handles response with nil mimeType")
        func handlesResponseWithNilMimeType() throws {
            let url = URL(string: "https://example.com")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            let response = try HAR.Response(from: httpResponse, data: Data())

            #expect(response.content.mimeType == "application/octet-stream")
        }

        @Test("encodes binary data as base64")
        func encodesBinaryDataAsBase64() throws {
            let url = URL(string: "https://example.com/image.png")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
            )!
            let binaryData = Data([0x89, 0x50, 0x4E, 0x47])  // PNG header

            let response = try HAR.Response(from: httpResponse, data: binaryData)

            #expect(response.content.encoding == "base64")
            #expect(response.content.text == binaryData.base64EncodedString())
        }

        @Test("handles empty response data")
        func handlesEmptyResponseData() throws {
            let url = URL(string: "https://example.com")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 204,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            let response = try HAR.Response(from: httpResponse, data: Data())

            #expect(response.bodySize == 0)
            #expect(response.content.size == 0)
        }
    }

    // MARK: - Content Tests

    @Suite("HAR.Content")
    struct ContentTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let content = HAR.Content(size: 500, mimeType: "text/plain")

            #expect(content.size == 500)
            #expect(content.compression == nil)
            #expect(content.mimeType == "text/plain")
            #expect(content.text == nil)
            #expect(content.encoding == nil)
            #expect(content.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let content = HAR.Content(
                size: 1000,
                compression: 200,
                mimeType: "application/json; charset=utf-8",
                text: "{\"data\":\"value\"}",
                encoding: nil,
                comment: "API response"
            )

            #expect(content.size == 1000)
            #expect(content.compression == 200)
            #expect(content.mimeType == "application/json; charset=utf-8")
            #expect(content.text == "{\"data\":\"value\"}")
            #expect(content.encoding == nil)
            #expect(content.comment == "API response")
        }

        @Test("supports base64 encoding")
        func base64Encoding() {
            let binaryData = Data([0x00, 0x01, 0x02])
            let content = HAR.Content(
                size: binaryData.count,
                mimeType: "application/octet-stream",
                text: binaryData.base64EncodedString(),
                encoding: "base64"
            )

            #expect(content.encoding == "base64")
            #expect(content.text == "AAEC")
        }
    }

    // MARK: - Header Tests

    @Suite("HAR.Header")
    struct HeaderTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let header = HAR.Header(name: "Authorization", value: "Bearer token123")

            #expect(header.name == "Authorization")
            #expect(header.value == "Bearer token123")
            #expect(header.comment == nil)
        }

        @Test("initializes with comment")
        func initWithComment() {
            let header = HAR.Header(
                name: "X-Custom-Header",
                value: "custom-value",
                comment: "Custom header for tracking"
            )

            #expect(header.comment == "Custom header for tracking")
        }
    }

    // MARK: - Cookie Tests

    @Suite("HAR.Cookie")
    struct CookieTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let cookie = HAR.Cookie(name: "session_id", value: "abc123")

            #expect(cookie.name == "session_id")
            #expect(cookie.value == "abc123")
            #expect(cookie.path == nil)
            #expect(cookie.domain == nil)
            #expect(cookie.expires == nil)
            #expect(cookie.httpOnly == nil)
            #expect(cookie.secure == nil)
            #expect(cookie.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let expiry = Date().addingTimeInterval(3600)
            let cookie = HAR.Cookie(
                name: "auth_token",
                value: "secure_value",
                path: "/api",
                domain: ".example.com",
                expires: expiry,
                httpOnly: true,
                secure: true,
                comment: "Authentication cookie"
            )

            #expect(cookie.name == "auth_token")
            #expect(cookie.value == "secure_value")
            #expect(cookie.path == "/api")
            #expect(cookie.domain == ".example.com")
            #expect(cookie.expires == expiry)
            #expect(cookie.httpOnly == true)
            #expect(cookie.secure == true)
            #expect(cookie.comment == "Authentication cookie")
        }
    }

    // MARK: - QueryParameter Tests

    @Suite("HAR.QueryParameter")
    struct QueryParameterTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let param = HAR.QueryParameter(name: "search", value: "swift testing")

            #expect(param.name == "search")
            #expect(param.value == "swift testing")
            #expect(param.comment == nil)
        }

        @Test("initializes with comment")
        func initWithComment() {
            let param = HAR.QueryParameter(
                name: "page",
                value: "1",
                comment: "Pagination parameter"
            )

            #expect(param.comment == "Pagination parameter")
        }
    }

    // MARK: - PostData Tests

    @Suite("HAR.PostData")
    struct PostDataTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let postData = HAR.PostData(mimeType: "application/x-www-form-urlencoded")

            #expect(postData.mimeType == "application/x-www-form-urlencoded")
            #expect(postData.params == nil)
            #expect(postData.text == nil)
            #expect(postData.comment == nil)
        }

        @Test("initializes with text")
        func initWithText() {
            let postData = HAR.PostData(
                mimeType: "application/json",
                text: "{\"username\":\"test\"}"
            )

            #expect(postData.mimeType == "application/json")
            #expect(postData.text == "{\"username\":\"test\"}")
        }

        @Test("initializes with params")
        func initWithParams() {
            let params = [
                HAR.PostData.Param(name: "username", value: "test"),
                HAR.PostData.Param(name: "password", value: "secret"),
            ]
            let postData = HAR.PostData(
                mimeType: "application/x-www-form-urlencoded",
                params: params
            )

            #expect(postData.params?.count == 2)
            #expect(postData.params?[0].name == "username")
            #expect(postData.params?[1].name == "password")
        }
    }

    // MARK: - PostData.Param Tests

    @Suite("HAR.PostData.Param")
    struct PostDataParamTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let param = HAR.PostData.Param(name: "field")

            #expect(param.name == "field")
            #expect(param.value == nil)
            #expect(param.fileName == nil)
            #expect(param.contentType == nil)
            #expect(param.comment == nil)
        }

        @Test("initializes with value")
        func initWithValue() {
            let param = HAR.PostData.Param(name: "email", value: "test@example.com")

            #expect(param.name == "email")
            #expect(param.value == "test@example.com")
        }

        @Test("initializes for file upload")
        func initForFileUpload() {
            let param = HAR.PostData.Param(
                name: "avatar",
                fileName: "profile.png",
                contentType: "image/png",
                comment: "User profile picture"
            )

            #expect(param.name == "avatar")
            #expect(param.fileName == "profile.png")
            #expect(param.contentType == "image/png")
            #expect(param.comment == "User profile picture")
        }
    }

    // MARK: - Timings Tests

    @Suite("HAR.Timings")
    struct TimingsTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let timings = HAR.Timings(send: 10, wait: 200, receive: 50)

            #expect(timings.blocked == nil)
            #expect(timings.dns == nil)
            #expect(timings.connect == nil)
            #expect(timings.send == 10)
            #expect(timings.wait == 200)
            #expect(timings.receive == 50)
            #expect(timings.ssl == nil)
            #expect(timings.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let timings = HAR.Timings(
                blocked: 5,
                dns: 20,
                connect: 50,
                send: 10,
                wait: 200,
                receive: 50,
                ssl: 30,
                comment: "Slow connection"
            )

            #expect(timings.blocked == 5)
            #expect(timings.dns == 20)
            #expect(timings.connect == 50)
            #expect(timings.send == 10)
            #expect(timings.wait == 200)
            #expect(timings.receive == 50)
            #expect(timings.ssl == 30)
            #expect(timings.comment == "Slow connection")
        }

        @Test("accepts -1 for unavailable timings")
        func unavailableTimings() {
            let timings = HAR.Timings(
                blocked: -1,
                dns: -1,
                connect: -1,
                send: 10,
                wait: 100,
                receive: 20,
                ssl: -1
            )

            #expect(timings.blocked == -1)
            #expect(timings.dns == -1)
            #expect(timings.connect == -1)
            #expect(timings.ssl == -1)
        }
    }

    // MARK: - Cache Tests

    @Suite("HAR.Cache Tests")
    struct CacheTests {
        @Test("initializes with default nil values")
        func initWithDefaults() {
            let cache = HAR.Cache()

            #expect(cache.beforeRequest == nil)
            #expect(cache.afterRequest == nil)
            #expect(cache.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let date = Date()
            let beforeEntry = HAR.Cache.CacheEntry(
                lastAccess: date,
                eTag: "\"abc123\"",
                hitCount: 5
            )
            let afterEntry = HAR.Cache.CacheEntry(
                expires: date.addingTimeInterval(3600),
                lastAccess: date,
                eTag: "\"abc123\"",
                hitCount: 6
            )

            let cache = HAR.Cache(
                beforeRequest: beforeEntry,
                afterRequest: afterEntry,
                comment: "Cache hit"
            )

            #expect(cache.beforeRequest != nil)
            #expect(cache.afterRequest != nil)
            #expect(cache.comment == "Cache hit")
        }
    }

    // MARK: - Cache.CacheEntry Tests

    @Suite("HAR.Cache.CacheEntry Tests")
    struct CacheEntryTests {
        @Test("initializes with required properties")
        func initWithRequiredProperties() {
            let date = Date()
            let entry = HAR.Cache.CacheEntry(
                lastAccess: date,
                eTag: "\"version1\"",
                hitCount: 10
            )

            #expect(entry.expires == nil)
            #expect(entry.lastAccess == date)
            #expect(entry.eTag == "\"version1\"")
            #expect(entry.hitCount == 10)
            #expect(entry.comment == nil)
        }

        @Test("initializes with all properties")
        func initWithAllProperties() {
            let lastAccess = Date()
            let expires = lastAccess.addingTimeInterval(86400)

            let entry = HAR.Cache.CacheEntry(
                expires: expires,
                lastAccess: lastAccess,
                eTag: "\"abc\"",
                hitCount: 100,
                comment: "Frequently accessed"
            )

            #expect(entry.expires == expires)
            #expect(entry.lastAccess == lastAccess)
            #expect(entry.eTag == "\"abc\"")
            #expect(entry.hitCount == 100)
            #expect(entry.comment == "Frequently accessed")
        }
    }

    // MARK: - HAR Static Methods Tests

    // MARK: - HAR.Entry from URLRequest/Response Tests

    @Suite("HAR.Entry from URLRequest/Response")
    struct EntryFromURLRequestTests {
        @Test("creates entry from URLRequest and HTTPURLResponse")
        func createsEntryFromURLRequest() throws {
            let url = URL(string: "https://example.com/api")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = "{}".data(using: .utf8)

            let response = HTTPURLResponse(
                url: url,
                statusCode: 201,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let responseData = "{\"id\":123}".data(using: .utf8)!
            let startTime = Date()
            let duration: TimeInterval = 0.5

            let entry = try HAR.Entry(
                request: request,
                response: response,
                data: responseData,
                startTime: startTime,
                duration: duration
            )

            #expect(entry.request.method == "POST")
            #expect(entry.request.url == "https://example.com/api")
            #expect(entry.response.status == 201)
            #expect(entry.time == 500)  // milliseconds
            #expect(entry.startedDateTime == startTime)
        }

        @Test("throws for URLRequest without URL")
        func throwsForRequestWithoutURL() {
            var request = URLRequest(url: URL(string: "about:blank")!)
            request.url = nil

            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            #expect(throws: ReplayError.self) {
                try HAR.Entry(
                    request: request,
                    response: response,
                    data: Data(),
                    startTime: Date(),
                    duration: 0.1
                )
            }
        }
    }

    @Suite("HAR Static Methods Tests")
    struct HARStaticMethodsTests {
        @Test("create returns valid log")
        func create() {
            let log = HAR.create()

            #expect(log.version == "1.2")
            #expect(log.creator.name == "Replay/1.0")
            #expect(log.creator.version == "1.0")
            #expect(log.entries.isEmpty)
        }

        @Test("create with custom creator")
        func createWithCustomCreator() {
            let log = HAR.create(creator: "MyApp/2.0")

            #expect(log.creator.name == "MyApp/2.0")
        }

        @Test("save and load roundtrip")
        func saveAndLoad() throws {
            var log = HAR.create()
            log.entries.append(makeTestEntry())
            log.comment = "Test HAR file"

            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("HARTests_saveAndLoad.har")

            try HAR.save(log, to: tempURL)
            let loaded = try HAR.load(from: tempURL)

            #expect(loaded.version == log.version)
            #expect(loaded.creator.name == log.creator.name)
            #expect(loaded.entries.count == log.entries.count)
            #expect(loaded.comment == "Test HAR file")

            try? FileManager.default.removeItem(at: tempURL)
        }

        @Test("save produces valid JSON")
        func saveProducesValidJSON() throws {
            let log = HAR.create()
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("HARTests_validJSON.har")

            try HAR.save(log, to: tempURL)
            let data = try Data(contentsOf: tempURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            #expect(json?["log"] != nil)

            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // MARK: - Codable Tests

    @Suite("HAR Codable Tests")
    struct HARCodableTests {
        @Test("all types are Codable")
        func allTypesAreCodable() throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds

            let log = HAR.Log(
                version: "1.2",
                creator: HAR.Creator(name: "Test", version: "1.0")
            )
            let logData = try encoder.encode(log)
            _ = try decoder.decode(HAR.Log.self, from: logData)

            let page = HAR.Page(
                startedDateTime: Date(),
                id: "p1",
                title: "Test",
                pageTimings: HAR.Page.PageTimings()
            )
            let pageData = try encoder.encode(page)
            _ = try decoder.decode(HAR.Page.self, from: pageData)

            let entry = makeTestEntry()
            let entryData = try encoder.encode(entry)
            _ = try decoder.decode(HAR.Entry.self, from: entryData)

            let cache = HAR.Cache(
                beforeRequest: HAR.Cache.CacheEntry(
                    lastAccess: Date(),
                    eTag: "\"test\"",
                    hitCount: 1
                )
            )
            let cacheData = try encoder.encode(cache)
            _ = try decoder.decode(HAR.Cache.self, from: cacheData)
        }

        @Test("encodes dates as ISO8601")
        func encodesDateAsISO8601() throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds

            let entry = makeTestEntry()
            let data = try encoder.encode(entry)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("startedDateTime"))
            #expect(json.contains("T"))
        }
    }

    // MARK: - Sendable Tests

    @Suite("HAR Sendable Tests")
    struct HARSendableTests {
        @Test("all types are Sendable")
        func allTypesAreSendable() async {
            let log = HAR.Log(
                version: "1.2",
                creator: HAR.Creator(name: "Test", version: "1.0")
            )

            await Task.detached {
                _ = log.version
            }.value
        }
    }
}

// MARK: - Test Helpers

private func makeTestRequest() -> HAR.Request {
    HAR.Request(
        method: "GET",
        url: "https://example.com/api",
        httpVersion: "HTTP/1.1",
        headers: [HAR.Header(name: "Accept", value: "application/json")],
        bodySize: 0
    )
}

private func makeTestResponse() -> HAR.Response {
    let content = HAR.Content(size: 2, mimeType: "text/plain", text: "OK")
    return HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: 2
    )
}

private func makeTestEntry() -> HAR.Entry {
    HAR.Entry(
        startedDateTime: Date(),
        time: 100,
        request: makeTestRequest(),
        response: makeTestResponse(),
        timings: HAR.Timings(send: 10, wait: 80, receive: 10)
    )
}
