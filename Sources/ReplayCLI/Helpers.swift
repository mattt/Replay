import Foundation

func findHARFiles(in root: URL, fileManager: FileManager) -> [URL] {
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

func referencedReplayNames(in testsRoot: URL, fileManager: FileManager) -> Set<String> {
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
