import ArgumentParser
import Foundation
import Replay

extension ReplayCommand {
    struct Validate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Validate a HAR file"
        )

        @Argument(help: "Path to HAR file")
        var path: String

        func run() async throws {
            let url = URL(fileURLWithPath: path)
            _ = try HAR.load(from: url)

            print("✓ Valid HAR archive")
        }
    }
}
