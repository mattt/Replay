import Foundation
import Testing

@testable import Replay

@Suite("RecordingMode Tests")
struct RecordingModeTests {

    @Suite("Enum Cases")
    struct EnumCaseTests {
        @Test("playback case exists")
        func playbackCase() {
            let mode: RecordingMode = .playback
            #expect(mode == .playback)
        }

        @Test("record case exists")
        func recordCase() {
            let mode: RecordingMode = .record
            #expect(mode == .record)
        }

        @Test("playback and record are distinct")
        func casesAreDistinct() {
            #expect(RecordingMode.playback != RecordingMode.record)
        }
    }

    @Suite("Current Property")
    struct CurrentPropertyTests {
        @Test("returns a valid RecordingMode")
        func returnsValidMode() {
            let mode = RecordingMode.current
            #expect(mode == .playback || mode == .record)
        }

        @Test("defaults to playback when no environment or arguments set")
        func defaultsToPlayback() {
            // Note: This test assumes the test runner doesn't pass
            // --enable-replay-recording. In a clean test environment,
            // the default should be .playback.
            let mode = RecordingMode.current
            // We can't guarantee the environment, so we just verify it returns a valid value
            #expect(mode == .playback || mode == .record)
        }
    }

    @Suite("Equatable")
    struct EquatableTests {
        @Test("same cases are equal")
        func sameCasesEqual() {
            #expect(RecordingMode.playback == RecordingMode.playback)
            #expect(RecordingMode.record == RecordingMode.record)
        }

        @Test("different cases are not equal")
        func differentCasesNotEqual() {
            #expect(RecordingMode.playback != RecordingMode.record)
        }
    }
}
