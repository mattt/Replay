import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("Cookie filter archive tests")
struct CookieFilterArchiveTests {
    @Test("Cookie header redaction removes parsed request and response secrets")
    func redactsCookieValues() async throws {
        let entry = try makeEntry()
        #expect(!entry.request.cookies.isEmpty)
        #expect(!entry.response.cookies.isEmpty)
        let filtered = await Filter.headers("cOoKiE", "SET-cookie", replacement: "[REDACTED]").apply(to: entry)

        #expect(filtered.request.cookies.map(\.value) == ["[REDACTED]", "[REDACTED]"])
        #expect(filtered.response.cookies.map(\.value) == ["[REDACTED]"])
        #expect(filtered.request.cookies.map(\.name) == entry.request.cookies.map(\.name))
        #expect(filtered.response.cookies.first?.path == entry.response.cookies.first?.path)
        #expect(filtered.response.cookies.first?.httpOnly == entry.response.cookies.first?.httpOnly)
        let archive = try encodedArchive(filtered)
        #expect(!archive.contains("request-cookie-secret"))
        #expect(!archive.contains("second-cookie-secret"))
        #expect(!archive.contains("response-cookie-secret"))
    }

    @Test("Header allowlisting removes the corresponding parsed cookies")
    func removesCookiesWithHeaders() async throws {
        let filtered = try await Filter.headers(keeping: ["Content-Type"]).apply(to: makeEntry())

        #expect(filtered.request.cookies.isEmpty)
        #expect(filtered.response.cookies.isEmpty)
        let archive = try encodedArchive(filtered)
        #expect(!archive.contains("request-cookie-secret"))
        #expect(!archive.contains("second-cookie-secret"))
        #expect(!archive.contains("response-cookie-secret"))
        #expect(filtered.response.headers.map(\.name) == ["Content-Type"])
    }

    @Test("Keeping cookie headers retains their parsed values")
    func preservesAllowedCookies() async throws {
        let entry = try makeEntry()
        let filtered = await Filter.headers(keeping: ["COOKIE", "set-cookie"]).apply(to: entry)

        #expect(filtered.request.cookies == entry.request.cookies)
        #expect(filtered.response.cookies == entry.response.cookies)
    }

    @Test("Filtering one cookie header does not change the other direction")
    func filtersDirectionsIndependently() async throws {
        let entry = try makeEntry()
        let requestFiltered = await Filter.headers("Cookie").apply(to: entry)
        let responseFiltered = await Filter.headers("Set-Cookie").apply(to: entry)
        let requestKept = await Filter.headers(keeping: ["Cookie"]).apply(to: entry)
        let responseKept = await Filter.headers(keeping: ["Set-Cookie"]).apply(to: entry)

        #expect(requestFiltered.response.cookies == entry.response.cookies)
        #expect(responseFiltered.request.cookies == entry.request.cookies)
        #expect(requestKept.request.cookies == entry.request.cookies)
        #expect(requestKept.response.cookies.isEmpty)
        #expect(responseKept.request.cookies.isEmpty)
        #expect(responseKept.response.cookies == entry.response.cookies)
    }

    @Test("Other header filters preserve cookies")
    func preservesUnrelatedCookies() async throws {
        let entry = try makeEntry()
        let filtered = await Filter.headers("Authorization").apply(to: entry)

        #expect(filtered.request.cookies == entry.request.cookies)
        #expect(filtered.response.cookies == entry.response.cookies)
    }

    private func makeEntry() throws -> HAR.Entry {
        var request = URLRequest(url: URL(string: "https://example.com/")!)
        request.setValue("session=request-cookie-secret; other=second-cookie-secret", forHTTPHeaderField: "Cookie")
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: [
                "Set-Cookie": "session=response-cookie-secret; Path=/; HttpOnly",
                "Content-Type": "text/plain",
            ]
        )!
        return try HAR.Entry(request: request, response: response, data: Data(), startTime: Date(), duration: 0)
    }

    private func encodedArchive(_ entry: HAR.Entry) throws -> String {
        var log = HAR.create()
        log.entries = [entry]
        return String(decoding: try HAR.encode(log), as: UTF8.self)
    }
}
