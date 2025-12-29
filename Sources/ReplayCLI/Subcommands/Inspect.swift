import ArgumentParser
import Foundation
import Replay

extension ReplayCommand {
    struct Inspect: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Inspect a HAR file"
        )

        @Argument(help: "Path to HAR file")
        var path: String

        func run() async throws {
            let url = URL(fileURLWithPath: path)
            let log = try HAR.load(from: url)

            print("HAR Archive: \(path)")
            print("Version: \(log.version)")
            print("Creator: \(log.creator.name) \(log.creator.version)")
            print("Entries: \(log.entries.count)")
            print()

            for (index, entry) in log.entries.enumerated() {
                print("[\(index + 1)] \(entry.request.method) \(entry.request.url)")
                print("    Status: \(entry.response.status) \(entry.response.statusText)")
                print("    Duration: \(entry.time)ms")
                print("    Size: \(entry.response.content.size) bytes")
            }
        }
    }
}
