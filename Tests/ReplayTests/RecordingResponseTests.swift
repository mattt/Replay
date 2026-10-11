import Foundation
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@testable import Replay

@Suite("Network response recording tests")
struct RecordingResponseTests {
    @Test("Completed empty responses are recorded and replayed", arguments: [("GET", 204), ("HEAD", 200)])
    func recordsEmptyResponse(method: String, status: Int) async throws {
        let server = try RecordingHTTPServer(
            response: "HTTP/1.1 \(status) OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        defer { withExtendedLifetime(server) {} }
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".har")
        defer { try? FileManager.default.removeItem(at: archive) }
        var request = URLRequest(url: server.url)
        request.httpMethod = method
        let session = try await Playback.session(configuration: .init(source: .file(archive), recordMode: .once))
        defer { session.invalidateAndCancel() }
        let key = try #require(
            session.configuration.httpAdditionalHeaders?[ReplayProtocolContext.headerName] as? String)
        request.setValue(key, forHTTPHeaderField: ReplayProtocolContext.headerName)
        let (data, response) = try await session.data(for: request)
        #expect(data.isEmpty)
        #expect((response as? HTTPURLResponse)?.statusCode == status)
        let log = try HAR.load(from: archive)
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.request.method == method)
        #expect(log.entries.first?.response.status == status)
        let replay = try await Playback.session(configuration: .init(source: .file(archive)))
        defer { replay.invalidateAndCancel() }
        let replayKey = try #require(
            replay.configuration.httpAdditionalHeaders?[ReplayProtocolContext.headerName] as? String)
        request.setValue(replayKey, forHTTPHeaderField: ReplayProtocolContext.headerName)
        let (replayedData, replayedResponse) = try await replay.data(for: request)
        #expect(replayedData.isEmpty)
        #expect((replayedResponse as? HTTPURLResponse)?.statusCode == status)
    }
}
