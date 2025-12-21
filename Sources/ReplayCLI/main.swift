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
            Clean.self,
        ]
    )

    // MARK: - Inspect

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

    // MARK: - Validate

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

    // MARK: - Filter

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

    // MARK: - Status Command

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show status of replay archives"
        )

        @Option(name: .long, help: "Path to search for replay archives (recursively)")
        var directory: String = "Tests"

        @Option(
            name: .long,
            help:
                "Path to search for tests (used to detect named archives and matcher configuration)"
        )
        var tests: String = "Tests"

        @Option(name: .long, help: "Warn when an archive is older than this many days")
        var warnAgeDays: Int = 30

        func run() async throws {
            let dirURL = URL(fileURLWithPath: directory)
            let testsURL = URL(fileURLWithPath: tests)

            let fileManager = FileManager.default
            let archives = findHARFiles(in: dirURL, fileManager: fileManager)
            let referencedNames = referencedReplayNames(in: testsURL, fileManager: fileManager)
            let matchersByName = referencedReplayMatchers(in: testsURL, fileManager: fileManager)

            print("Replay Archives Status")
            print("======================")
            print("Directory: \(directory)")
            print("Tests: \(tests)")
            print()

            var totalSize = 0
            var totalEntries = 0
            let warnAgeSeconds = TimeInterval(warnAgeDays) * 86400

            for archiveURL in archives {
                let log = try HAR.load(from: archiveURL)
                let values = try archiveURL.resourceValues(forKeys: [
                    .fileSizeKey, .creationDateKey,
                ])
                let size = values.fileSize ?? 0

                totalSize += size
                totalEntries += log.entries.count

                print("📼 \(archiveURL.lastPathComponent)")
                print("   Entries: \(log.entries.count)")
                print(
                    "   Size: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
                )

                let name = archiveURL.deletingPathExtension().lastPathComponent
                if !referencedNames.isEmpty, !referencedNames.contains(name) {
                    print("   ⚠️  Orphaned (no `.replay(\"\(name)\")` reference found in \(tests))")
                }

                if let matchers = matchersByName[name], !matchers.isEmpty {
                    print("   Matchers: \(matchers.joined(separator: ", "))")
                }

                if let created = values.creationDate {
                    let age = Date().timeIntervalSince(created)
                    if age > warnAgeSeconds {
                        let days = Int(age / 86400)
                        print("   ⚠️  Archive is \(days) days old")
                    }
                }

                print()
            }

            print("Total archives: \(archives.count)")
            print("Total entries: \(totalEntries)")
            print(
                "Total size: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))"
            )
        }

        private func referencedReplayMatchers(
            in testsRoot: URL,
            fileManager: FileManager
        ) -> [String: [String]] {
            guard
                let enumerator = fileManager.enumerator(
                    at: testsRoot,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            else { return [:] }

            // Capture occurrences like:
            //   .replay("fetchUser", matching: .method, .path, filters: ...)
            // This is best-effort parsing for CLI reporting.
            let pattern = #"\.replay\(\s*"([^"]+)"\s*,\s*matching:\s*([^\)]*)\)"#
            guard let regex = try? Regex(pattern, as: (Substring, Substring, Substring).self) else { return [:] }

            var map: [String: [String]] = [:]

            for case let url as URL in enumerator {
                guard url.pathExtension == "swift" else { continue }
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }

                for match in contents.matches(of: regex) {
                    let name = String(match.output.1)
                    let raw = String(match.output.2)

                    // Stop at the next argument label if present (e.g. `filters:`).
                    let trimmed: Substring
                    if let idx = raw.firstIndex(of: ":") {
                        trimmed = raw[..<idx]
                    } else {
                        trimmed = raw[...]
                    }

                    let parts =
                        trimmed
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

                    var matchers: [String] = []
                    for part in parts {
                        guard part.hasPrefix(".") else { continue }
                        // Keep the leading `.foo` portion (strip arguments like `.headers(...)`).
                        let head = part.split(
                            separator: "(", maxSplits: 1, omittingEmptySubsequences: true
                        ).first
                        if let head {
                            matchers.append(String(head))
                        }
                    }

                    if !matchers.isEmpty {
                        map[name] = matchers
                    }
                }
            }

            return map
        }
    }

    // MARK: - Clean

    struct Clean: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete orphaned replay archives"
        )

        @Option(name: .long, help: "Path to search for replay archives (recursively)")
        var directory: String = "Tests"

        @Option(name: .long, help: "Path to search for tests (used to detect named archives)")
        var tests: String = "Tests"

        @Flag(name: .shortAndLong, help: "Perform deletion (default is dry-run)")
        var force: Bool = false

        func run() async throws {
            let dirURL = URL(fileURLWithPath: directory)
            let testsURL = URL(fileURLWithPath: tests)
            let fileManager = FileManager.default

            let archives = findHARFiles(in: dirURL, fileManager: fileManager)
            let referencedNames = referencedReplayNames(in: testsURL, fileManager: fileManager)

            let orphans = archives.filter { url in
                let name = url.deletingPathExtension().lastPathComponent
                return !referencedNames.contains(name)
            }

            if orphans.isEmpty {
                print("No orphaned archives found.")
                return
            }

            if !force {
                print("Dry run: would delete \(orphans.count) orphaned archive(s):")
                for url in orphans {
                    print("  \(url.path)")
                }
                print()
                print("Use --force to delete.")
                return
            }

            var deleted = 0
            for url in orphans {
                do {
                    try fileManager.removeItem(at: url)
                    deleted += 1
                    print("Deleted \(url.path)")
                } catch {
                    print("Failed to delete \(url.path): \(error)")
                }
            }

            print("Deleted \(deleted) orphaned archive(s).")
        }
    }

    // MARK: - Record

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
                "--enable-replay-recording",
            ]
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["REPLAY_RECORD": "1"],
                uniquingKeysWith: { _, new in new }
            )

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

// MARK: - Helpers

private func findHARFiles(in root: URL, fileManager: FileManager) -> [URL] {
    guard
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    else { return [] }

    var harFiles: [URL] = []
    for case let url as URL in enumerator {
        guard url.pathExtension == "har" else { continue }
        harFiles.append(url)
    }
    return harFiles.sorted { $0.path < $1.path }
}

private func referencedReplayNames(in testsRoot: URL, fileManager: FileManager) -> Set<String> {
    guard
        let enumerator = fileManager.enumerator(
            at: testsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    else { return [] }

    var names: Set<String> = []
    let pattern = #"\.replay\(\s*"([^"]+)""#
    guard let regex = try? Regex(pattern, as: (Substring, Substring).self) else { return [] }

    for case let url as URL in enumerator {
        guard url.pathExtension == "swift" else { continue }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }

        for match in contents.matches(of: regex) {
            names.insert(String(match.output.1))
        }
    }

    return names
}
