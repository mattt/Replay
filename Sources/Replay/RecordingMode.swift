import Foundation

/// Determines whether tests should only replay from archives or actively record.
public enum RecordingMode {
    /// Only replay from archives
    case playback

    /// Explicitly requested recording
    case record

    /// The current recording mode.
    ///
    /// - Returns: `.record` if `--enable-replay-recording` is present in the command line arguments;
    ///            otherwise returns `.playback`.
    public static var current: RecordingMode {
        if CommandLine.arguments.contains("--enable-replay-recording") {
            return .record
        }

        return .playback
    }
}
