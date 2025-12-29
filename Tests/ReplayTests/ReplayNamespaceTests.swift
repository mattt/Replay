import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import Replay

@Suite("Replay Namespace Tests")
struct ReplayNamespaceTests {

    @Suite("Replay.session Tests")
    struct SessionTests {
        @Test("session has PlaybackURLProtocol configured")
        func sessionHasPlaybackProtocol() {
            let session = Replay.session
            let protocols = session.configuration.protocolClasses ?? []
            let hasPlayback = protocols.contains { $0 == PlaybackURLProtocol.self }
            #expect(hasPlayback)
        }
    }

    @Suite("Replay.configure Tests")
    struct ConfigureTests {
        @Test("configure inserts PlaybackURLProtocol at index 0")
        func configureInsertsProtocol() {
            let config = URLSessionConfiguration.default
            Replay.configure(config)

            let protocols = config.protocolClasses ?? []
            #expect(!protocols.isEmpty)
            #expect(protocols.first == PlaybackURLProtocol.self)
        }

        @Test("configure is idempotent")
        func configureIsIdempotent() {
            let config = URLSessionConfiguration.default
            Replay.configure(config)
            Replay.configure(config)
            Replay.configure(config)

            let protocols = config.protocolClasses ?? []
            let playbackCount = protocols.filter { $0 == PlaybackURLProtocol.self }.count
            #expect(playbackCount == 1)
        }

        @Test("configure preserves existing protocols")
        func configurePreservesExistingProtocols() {
            let config = URLSessionConfiguration.default
            let originalCount = config.protocolClasses?.count ?? 0

            Replay.configure(config)

            let newCount = config.protocolClasses?.count ?? 0
            #expect(newCount == originalCount + 1)
        }
    }

    @Suite("Replay.configuration Tests")
    struct ConfigurationMethodTests {
        @Test("configuration returns configured URLSessionConfiguration")
        func configurationReturnsConfigured() {
            let config = Replay.configuration()

            let protocols = config.protocolClasses ?? []
            let hasPlayback = protocols.contains { $0 == PlaybackURLProtocol.self }
            #expect(hasPlayback)
        }

        @Test("configuration uses default base by default")
        func configurationUsesDefaultBase() {
            let config = Replay.configuration()
            #expect(config.urlCache != nil)
        }

        @Test("configuration accepts custom base configuration")
        func configurationAcceptsCustomBase() {
            let ephemeral = URLSessionConfiguration.ephemeral
            let config = Replay.configuration(base: ephemeral)

            let protocols = config.protocolClasses ?? []
            let hasPlayback = protocols.contains { $0 == PlaybackURLProtocol.self }
            #expect(hasPlayback)
        }
    }

    @Suite("Replay.makeSession Tests")
    struct MakeSessionTests {
        @Test("makeSession returns URLSession with Replay configured")
        func makeSessionReturnsConfiguredSession() {
            let session = Replay.makeSession()

            let protocols = session.configuration.protocolClasses ?? []
            let hasPlayback = protocols.contains { $0 == PlaybackURLProtocol.self }
            #expect(hasPlayback)
        }

        @Test("makeSession uses default configuration by default")
        func makeSessionUsesDefaultConfiguration() {
            let session = Replay.makeSession()
            #expect(session.configuration.urlCache != nil)
        }

        @Test("makeSession accepts custom configuration")
        func makeSessionAcceptsCustomConfiguration() {
            let ephemeral = URLSessionConfiguration.ephemeral
            let session = Replay.makeSession(configuration: ephemeral)

            let protocols = session.configuration.protocolClasses ?? []
            let hasPlayback = protocols.contains { $0 == PlaybackURLProtocol.self }
            #expect(hasPlayback)
        }
    }

    @Suite("Replay.session Tests with ReplayContext")
    struct SessionWithContextTests {
        @Test("session sets header when ReplayContext has playbackStore")
        func sessionSetsHeaderWithContext() async throws {
            // Create a test store
            let testStore = PlaybackStore()
            let testConfig = PlaybackConfiguration(
                source: .stubs([Stub.get("https://example.com", 200, [:], { "OK" })])
            )
            try await testStore.configure(testConfig)

            // Set the context
            ReplayContext.$playbackStore.withValue(testStore) {
                let session = Replay.session
                let headers = session.configuration.httpAdditionalHeaders as? [String: String]
                let headerValue = headers?[ReplayProtocolContext.headerName]

                #expect(headerValue != nil)
                #expect(headerValue == PlaybackStoreRegistry.key(for: testStore))
            }
        }

        @Test("session does not set header when ReplayContext is nil")
        func sessionDoesNotSetHeaderWithoutContext() {
            let session = Replay.session
            let headers = session.configuration.httpAdditionalHeaders as? [String: String]
            let headerValue = headers?[ReplayProtocolContext.headerName]

            #expect(headerValue == nil)
        }
    }
}
