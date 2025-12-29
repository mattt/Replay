import ArgumentParser
import Foundation
import Replay

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

func main() {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await ReplayCommand.main()
        semaphore.signal()
    }
    semaphore.wait()
}

main()
