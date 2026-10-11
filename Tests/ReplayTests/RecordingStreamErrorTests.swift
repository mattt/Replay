import Foundation
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@testable import Replay

@Suite("Network recording transport errors")
struct RecordingStreamErrorTests {
    @Test(
        "A truncated response fails without saving a fixture",
        arguments: [Replay.PlaybackMode.strict, .passthrough, .live], [0, 16392])
    func truncatedResponse(mode: Replay.PlaybackMode, bodySize: Int) async throws {
        let server = try RecordingHTTPServer(
            response: "HTTP/1.1 200 OK\r\nContent-Length: 1000000\r\nConnection: close\r\n\r\n"
                + String(repeating: "x", count: bodySize)
        )
        defer { withExtendedLifetime(server) {} }
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".har")
        defer { try? FileManager.default.removeItem(at: archive) }
        let session = try await Playback.session(
            configuration: .init(source: .file(archive), playbackMode: mode, recordMode: .once))
        defer { session.invalidateAndCancel() }
        let key = try #require(
            session.configuration.httpAdditionalHeaders?[ReplayProtocolContext.headerName] as? String)
        var request = URLRequest(url: server.url)
        request.setValue(key, forHTTPHeaderField: ReplayProtocolContext.headerName)
        do {
            _ = try await session.data(for: request)
            Issue.record("A truncated response must fail")
        } catch {
            #expect((error as NSError).domain == NSURLErrorDomain)
        }
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        let store = try #require(PlaybackStoreRegistry.shared.store(for: key))
        await store.flush()
        #expect(await store.getAvailableEntries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
    }
    #if !canImport(FoundationNetworking)
        @Test("Explicit flushing still records an active event stream once")
        func flushEventStream() async throws {
            let body = "data: hello\n\n"
            let server = try RecordingHTTPServer(
                response: "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n" + body,
                holdOpen: true
            )
            defer { withExtendedLifetime(server) {} }
            let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".har")
            defer { try? FileManager.default.removeItem(at: archive) }
            let session = try await Playback.session(configuration: .init(source: .file(archive), recordMode: .once))
            defer { session.invalidateAndCancel() }
            let key = try #require(
                session.configuration.httpAdditionalHeaders?[ReplayProtocolContext.headerName] as? String)
            let store = try #require(PlaybackStoreRegistry.shared.store(for: key))
            let (bytes, _) = try await session.bytes(from: server.url)
            var received = Data()
            for try await byte in bytes {
                received.append(byte)
                if received.count == body.utf8.count {
                    await store.flush()
                }
            }
            let log = try HAR.load(from: archive)
            #expect(log.entries.count == 1)
            #expect(log.entries.first?.response.content.text == body)
            await store.flush()
            #expect(try HAR.load(from: archive).entries.count == 1)
        }
    #endif

}
