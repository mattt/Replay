import ArgumentParser
import Foundation
import Replay

extension ReplayCommand {
    struct FilterCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "filter",
            abstract: "Filter headers and query parameters from a HAR file"
        )

        @Argument(help: "Input HAR file")
        var input: String

        @Argument(help: "Output HAR file")
        var output: String

        @Option(name: .long, help: "Header names to filter")
        var headers: [String] = []

        @Option(name: .long, help: "Query parameters to filter")
        var queryParams: [String] = []

        func run() async throws {
            let inputURL = URL(fileURLWithPath: input)
            let outputURL = URL(fileURLWithPath: output)

            var log = try HAR.load(from: inputURL)

            var filters: [Filter] = []
            if !headers.isEmpty {
                filters.append(.headers(removing: headers))
            }
            if !queryParams.isEmpty {
                filters.append(.queryParameters(removing: queryParams))
            }

            for index in log.entries.indices {
                var entry = log.entries[index]
                for filter in filters {
                    entry = await filter.apply(to: entry)
                }
                log.entries[index] = entry
            }

            try HAR.save(log, to: outputURL)
            print("✓ Filtered archive saved to \(output)")
        }
    }
}
