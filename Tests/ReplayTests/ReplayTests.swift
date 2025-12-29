import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Test
func harRoundTrip() throws {
    var log = HAR.create(creator: "ReplayTests/1.0")

    let started = Date()
    let request = HAR.Request(
        method: "GET",
        url: "https://example.com/users",
        httpVersion: "HTTP/1.1",
        headers: [],
        bodySize: 0
    )

    let content = HAR.Content(
        size: 2,
        mimeType: "text/plain",
        text: "OK"
    )

    let response = HAR.Response(
        status: 200,
        statusText: "OK",
        httpVersion: "HTTP/1.1",
        headers: [],
        content: content,
        bodySize: content.size
    )

    let timings = HAR.Timings(send: 0, wait: 5, receive: 0)

    let entry = HAR.Entry(
        startedDateTime: started,
        time: 5,
        request: request,
        response: response,
        timings: timings
    )

    log.entries.append(entry)

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ReplayTests_harRoundTrip.har")

    try HAR.save(log, to: tempURL)
    let loaded = try HAR.load(from: tempURL)

    if loaded.entries.count != log.entries.count {
        Issue.record("Expected \(log.entries.count) entries, got \(loaded.entries.count)")
    }
}

@Test
func replayConfigurationInsertsProtocol() {
    let config = URLSessionConfiguration.default
    Replay.configure(config)

    let protocols = config.protocolClasses ?? []
    let hasPlayback = protocols.contains { $0 == PlaybackURLProtocol.self }

    if !hasPlayback {
        Issue.record(
            "PlaybackURLProtocol was not inserted into URLSessionConfiguration.protocolClasses")
    }
}
