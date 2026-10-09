import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("Query filter archive tests")
struct QueryFilterArchiveTests {
    @Test("Redaction removes repeated and encoded query secrets from the archive")
    func redactsURLAndQueryList() async throws {
        let request = URLRequest(
            url: URL(
                string: "https://example.com/items?to%6Ben=query-secret-one&token=query-secret-two&page=1#section")!
        )
        let entry = try makeEntry(request)
        let filtered = await Filter.queryParameters("token").apply(to: entry)
        let items = try #require(URLComponents(string: filtered.request.url)?.queryItems)

        #expect(items.map(\.name) == ["token", "token", "page"])
        #expect(items.map(\.value) == ["[FILTERED]", "[FILTERED]", "1"])
        #expect(filtered.request.queryString.map(\.value) == ["[FILTERED]", "[FILTERED]", "1"])
        #expect(URLComponents(string: filtered.request.url)?.fragment == "section")
        let archive = try encodedArchive(filtered)
        #expect(!archive.contains("query-secret-one"))
        #expect(!archive.contains("query-secret-two"))

        let store = PlaybackStore()
        try await store.configure(
            PlaybackConfiguration(source: .entries([filtered]), matchers: [.method, .host, .path])
        )
        let (response, data) = try await store.handleRequest(request)
        #expect(response.statusCode == 200)
        #expect(data == Data("response".utf8))
    }

    @Test("Allowlisting removes query secrets from both stored representations")
    func keepsAllowedParameters() async throws {
        let request = URLRequest(url: URL(string: "https://example.com/?token=query-secret&page=1&page=2")!)
        let filtered = try await Filter.queryParameters(keeping: ["page"]).apply(to: makeEntry(request))

        #expect(filtered.request.url == "https://example.com/?page=1&page=2")
        #expect(filtered.request.queryString.map(\.name) == ["page", "page"])
        let archive = try encodedArchive(filtered)
        #expect(!archive.contains("query-secret"))
    }

    @Test("An empty allowlist removes the URL query")
    func removesAllParameters() async throws {
        let entry = try makeEntry(URLRequest(url: URL(string: "https://example.com/?token=query-secret#section")!))
        let filtered = await Filter.queryParameters(keeping: [String]()).apply(to: entry)

        #expect(filtered.request.url == "https://example.com/#section")
        #expect(filtered.request.queryString.isEmpty)
        let archive = try encodedArchive(filtered)
        #expect(!archive.contains("query-secret"))
    }

    @Test("Unchanged URLs retain their original encoding")
    func preservesUnchangedURL() async throws {
        let request = URLRequest(url: URL(string: "https://example.com/?TOKEN=allowed&path=%2f&a&b=#section")!)
        let entry = try makeEntry(request)
        let redacted = await Filter.queryParameters("token").apply(to: entry)
        let kept = await Filter.queryParameters(keeping: ["TOKEN", "path", "a", "b"]).apply(to: entry)

        #expect(redacted.request.url == entry.request.url)
        #expect(kept.request.url == entry.request.url)
        #expect(redacted.request.queryString == entry.request.queryString)
    }

    @Test("Custom replacements preserve query syntax")
    func escapesReplacement() async throws {
        let entry = try makeEntry(URLRequest(url: URL(string: "https://example.com/?token=secret&page=1")!))
        let filtered = await Filter.queryParameters("token", replacement: "a&b=c#d").apply(to: entry)
        let items = try #require(URLComponents(string: filtered.request.url)?.queryItems)

        #expect(items == [URLQueryItem(name: "token", value: "a&b=c#d"), URLQueryItem(name: "page", value: "1")])
    }

    @Test("Filtering preserves the raw encoding of unrelated parameters")
    func preservesEncodingWhileFiltering() async throws {
        let request = URLRequest(
            url: URL(string: "https://example.com/?token=query-secret&path=%2f&encoded=%41&space=+&a&b=")!
        )
        let entry = try makeEntry(request)
        let redacted = await Filter.queryParameters("token", replacement: "redacted").apply(to: entry)
        let kept = await Filter.queryParameters(keeping: ["path", "encoded", "space", "a", "b"]).apply(to: entry)

        #expect(redacted.request.url == "https://example.com/?token=redacted&path=%2f&encoded=%41&space=+&a&b=")
        #expect(kept.request.url == "https://example.com/?path=%2f&encoded=%41&space=+&a&b=")
        let redactedArchive = try encodedArchive(redacted)
        let keptArchive = try encodedArchive(kept)
        #expect(!redactedArchive.contains("query-secret"))
        #expect(!keptArchive.contains("query-secret"))
    }

    @Test("Unsafe imported URLs lose their query instead of retaining secrets")
    func removesUnparseableQueries() async throws {
        for (url, expectedURL) in [
            ("https://exa mple.com/?token=query-secret#section", "https://exa mple.com/#section"),
            ("https://[invalid/?token=query-secret&page=1", "https://[invalid/"),
            ("https://example.com/?token=query-secret&bad=%FF", "https://example.com/"),
            ("https://example.com/?%FF=query-secret", "https://example.com/"),
        ] {
            var entry = try makeEntry(URLRequest(url: URL(string: "https://example.com/")!))
            entry.request.url = url
            entry.request.queryString = [
                HAR.QueryParameter(name: "token", value: "query-secret"),
                HAR.QueryParameter(name: "page", value: "additional-query-secret"),
            ]

            let redacted = await Filter.queryParameters("token").apply(to: entry)
            let kept = await Filter.queryParameters(keeping: ["page"]).apply(to: entry)
            #expect(redacted.request.url == expectedURL)
            #expect(kept.request.url == expectedURL)
            #expect(redacted.request.queryString.isEmpty)
            #expect(kept.request.queryString.isEmpty)
            let redactedArchive = try encodedArchive(redacted)
            let keptArchive = try encodedArchive(kept)
            #expect(!redactedArchive.contains("query-secret"))
            #expect(!keptArchive.contains("query-secret"))
        }
    }

    @Test("Malformed URLs without a query retain their path and fragment")
    func preservesMalformedURLWithoutQuery() async throws {
        var entry = try makeEntry(URLRequest(url: URL(string: "https://example.com/")!))
        entry.request.url = "https://[invalid]/#section?token=fragment-value"
        let filtered = await Filter.queryParameters("token").apply(to: entry)

        #expect(filtered.request.url == entry.request.url)
    }

    @Test("Default playback applies query policies after recording and reloading")
    func defaultPlaybackWithQueryPolicies() async throws {
        for policy in [
            Filter.queryParameters("token", replacement: "a&b=c#d"),
            Filter.queryParameters(keeping: ["page", "path"]),
        ] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".har")
            defer { try? FileManager.default.removeItem(at: file) }
            let store = PlaybackStore()
            try await store.configure(PlaybackConfiguration(source: .file(file), recordMode: .once, filters: [policy]))
            for page in [1, 2] {
                let request = URLRequest(
                    url: URL(string: "https://example.com/?to%6Ben=secret&token=other&page=\(page)&path=%2f")!)
                try await store.recordResponse(
                    request: request,
                    response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: Data("page-\(page)".utf8), duration: 0, startTime: Date()
                )
                let (_, data) = try await store.handleRequest(request)
                #expect(data == Data("page-\(page)".utf8))
            }
            let reloaded = PlaybackStore()
            try await reloaded.configure(PlaybackConfiguration(source: .file(file), filters: [policy]))
            for page in [1, 2] {
                let request = URLRequest(
                    url: URL(string: "https://example.com/?to%6Ben=new&token=new&page=\(page)&path=%2f")!)
                let (_, data) = try await reloaded.handleRequest(request)
                #expect(data == Data("page-\(page)".utf8))
            }
            let missing = URLRequest(url: URL(string: "https://example.com/?token=new&page=3&path=%2f")!)
            guard case .error = try await reloaded.checkRequest(missing) else {
                Issue.record("An unrecorded page must not match")
                continue
            }
            #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("secret"))
        }
    }

    @Test("Query policies preserve strict and custom matching contracts")
    func matchingContracts() async throws {
        let original = URLRequest(url: URL(string: "https://example.com/?token=secret&page=1&path=%2f")!)
        let policy = Filter.queryParameters("token")
        let entry = try await policy.apply(to: makeEntry(original))
        #expect([Matcher].default.firstMatch(for: original, in: [entry]) == nil)
        #expect([Matcher].default.firstMatch(for: original, in: [entry], filters: [policy]) != nil)
        let differentEncoding = URLRequest(url: URL(string: "https://example.com/?token=secret&page=1&path=/")!)
        #expect([Matcher].default.firstMatch(for: differentEncoding, in: [entry], filters: [policy]) == nil)
        #expect([Matcher.method, .query].firstMatch(for: original, in: [entry], filters: [policy]) != nil)
        let custom = Matcher.custom { incoming, _ in incoming.url == original.url }
        #expect([custom].firstMatch(for: original, in: [entry], filters: [policy]) != nil)
        let customFilter = Filter.custom { _ in
            Issue.record("Custom filters must not run during matching")
            return entry
        }
        #expect([Matcher].default.firstMatch(for: original, in: [entry], filters: [customFilter]) == nil)
        var unsafe = entry
        unsafe.request.url = "https://example.com/?token=%FF&page=1"
        #expect([Matcher].default.firstMatch(for: original, in: [unsafe], filters: [policy]) == nil)
        #expect([Matcher].default.firstMatch(for: original, in: [try makeEntry(original)], filters: [policy]) != nil)
    }

    private func makeEntry(_ request: URLRequest) throws -> HAR.Entry {
        try HAR.Entry(
            request: request,
            response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
            data: Data("response".utf8),
            startTime: Date(),
            duration: 0
        )
    }

    private func encodedArchive(_ entry: HAR.Entry) throws -> String {
        var log = HAR.create()
        log.entries = [entry]
        return String(decoding: try HAR.encode(log), as: UTF8.self)
    }
}
