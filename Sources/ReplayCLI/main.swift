import ArgumentParser
import Foundation
import Replay

@main
struct ReplayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "replay",
        abstract: "HTTP recording and playback utilities",
        subcommands: [
            Inspect.self,
            Validate.self,
            FilterCommand.self,
            Record.self,
            Status.self,
        ]
    )
}
