import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

// URLProtocol works differently on Linux; these tests rely on Apple-specific behavior
#if !canImport(FoundationNetworking)
    @Suite("Local Scope Tests")
    struct LocalScopeTests {

        @Test("Local scope isolates PlaybackStore across concurrent scopes")
        func localScopeIsolation() async throws {
            let current = try #require(Test.current)

            let url = URL(string: "https://example.com/value")!

            let traitA = ReplayTrait(
                nil,
                matchers: .default,
                directory: "Replays",
                stubs: [Stub(.get, url, body: "A")],
                scope: .test
            )

            let traitB = ReplayTrait(
                nil,
                matchers: .default,
                directory: "Replays",
                stubs: [Stub(.get, url, body: "B")],
                scope: .test
            )

            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await traitA.provideScope(for: current, testCase: nil) {
                        let (data, _) = try await Replay.session.data(from: url)
                        let value = try #require(String(data: data, encoding: .utf8))
                        #expect(value == "A")
                        return
                    }
                    return "A"
                }

                group.addTask {
                    try await traitB.provideScope(for: current, testCase: nil) {
                        let (data, _) = try await Replay.session.data(from: url)
                        let value = try #require(String(data: data, encoding: .utf8))
                        #expect(value == "B")
                        return
                    }
                    return "B"
                }

                var results: [String] = []
                for try await value in group {
                    results.append(value)
                }

                #expect(Set(results) == ["A", "B"])
            }
        }
    }
#endif
