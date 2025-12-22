import Foundation
import Testing

@testable import Replay

@Suite("Stub Playback Tests", .serialized)
struct StubTests {

    @Test(
        "ReplayTrait can replay from in-memory stubs (global scope)",
        .replay(stubs: [Stub(URL(string: "https://example.com/hello")!, body: "OK")])
    )
    func replayFromStubs() async throws {
        let url = URL(string: "https://example.com/hello")!

        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "OK")
    }
}
