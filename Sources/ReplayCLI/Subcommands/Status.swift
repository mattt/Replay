import ArgumentParser
import Foundation
import Replay

extension ReplayCommand {
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
            //   .replay("fetchUser", matching: [.method, .path], filters: ...)
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
                        // Handle array syntax like `[.method, .path]`
                        let cleanPart = part.trimmingCharacters(in: ["[", "]"])
                        guard cleanPart.hasPrefix(".") else { continue }

                        // Keep the leading `.foo` portion (strip arguments like `.headers(...)`).
                        let head = cleanPart.split(
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
}
