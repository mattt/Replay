import ArgumentParser
import Foundation
import Replay

extension ReplayCommand {
    struct Record: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Record HTTP traffic for specific tests"
        )

        @Argument(help: "Test name filter")
        var filter: String

        @Flag(name: .long, help: "Overwrite existing archive")
        var force: Bool = false

        func run() async throws {
            print("Recording HTTP traffic for test: \(filter)")
            print()

            let replayDirectory = "Tests/Replays"
            let archivePath = "\(replayDirectory)/\(filter).har"

            if !force && FileManager.default.fileExists(atPath: archivePath) {
                print("⚠️  Archive already exists: \(archivePath)")
                print("    Use --force to overwrite")
                throw ExitCode.failure
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swift",
                "test",
                "--filter",
                filter,
            ]
            var env = ProcessInfo.processInfo.environment
            env["REPLAY_RECORD_MODE"] = force ? "rewrite" : "once"
            process.environment = env

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                print()
                print("✓ Recording complete: \(archivePath)")
            } else {
                print()
                print("✗ Recording failed")
                throw ExitCode.failure
            }
        }
    }
}
