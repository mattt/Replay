import Foundation
import Testing

@testable import Replay

private final class TestBundleToken {}

/// The `Replays/` directory next to this source file.
///
/// `Tests/ReplayTests` declares no resources,
/// so the archive in it is reachable only through source-relative resolution.
private let sourceReplaysURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Replays")

@Suite("Archive Resolution Tests", .serialized)
struct ArchiveResolutionTests {
    @Test("Playback prefers an archive next to the test source over a bundle root")
    func playbackPrefersSourceTreeOverBundle() async throws {
        let test = try #require(Test.current)
        let isolation = PlaybackIsolationTrait(replaysFrom: Bundle(for: TestBundleToken.self))
        let trait = ReplayTrait("source_relative")

        // Throws `archiveMissing` if resolution lands in the bundle,
        // which has no `Replays/source_relative.har`.
        try await isolation.provideScope(for: test, testCase: nil) {
            try await trait.provideScope(for: test, testCase: nil, performing: {})
        }
    }

    @Test("Recording targets the test source tree when the root is a bundle")
    func recordingTargetsSourceTreeWhenRootIsBundle() async throws {
        let test = try #require(Test.current)
        let bundleRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let isolation = PlaybackIsolationTrait(root: .bundle(bundleRoot))
        let trait = ReplayTrait("recorded_next_to_source")

        try await isolation.provideScope(for: test, testCase: nil) {
            let url = try await trait.resolveArchiveURL(name: "recorded_next_to_source", test: test, recordMode: .once)
            let expected = sourceReplaysURL.appendingPathComponent("recorded_next_to_source.har")
            #expect(url.standardizedFileURL == expected.standardizedFileURL)
        }
    }

    @Test("Playback falls back to the bundle root when the source tree has no archive")
    func playbackFallsBackToBundleRoot() async throws {
        let test = try #require(Test.current)
        let bundleRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let isolation = PlaybackIsolationTrait(root: .bundle(bundleRoot))
        let trait = ReplayTrait("not_in_source_tree")

        try await isolation.provideScope(for: test, testCase: nil) {
            let url = try await trait.resolveArchiveURL(name: "not_in_source_tree", test: test, recordMode: .none)
            #expect(url == bundleRoot.appendingPathComponent("not_in_source_tree.har"))
        }
    }

    @Test("An explicit root URL wins over the source tree for playback and recording")
    func explicitRootWinsOverSourceTree() async throws {
        let test = try #require(Test.current)
        let explicitRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let isolation = PlaybackIsolationTrait(replaysRootURL: explicitRoot)
        let trait = ReplayTrait("source_relative")

        try await isolation.provideScope(for: test, testCase: nil) {
            for recordMode in Replay.RecordMode.allCases {
                let url = try await trait.resolveArchiveURL(name: "source_relative", test: test, recordMode: recordMode)
                #expect(url == explicitRoot.appendingPathComponent("source_relative.har"))
            }
        }
    }

    @Test("A trait-level root URL wins over everything")
    func traitRootWinsOverEverything() async throws {
        let test = try #require(Test.current)
        let traitRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let isolation = PlaybackIsolationTrait(replaysRootURL: sourceReplaysURL)
        let trait = ReplayTrait("source_relative", rootURL: traitRoot)

        try await isolation.provideScope(for: test, testCase: nil) {
            let url = try await trait.resolveArchiveURL(name: "source_relative", test: test, recordMode: .once)
            #expect(url == traitRoot.appendingPathComponent("source_relative.har"))
        }
    }
}
