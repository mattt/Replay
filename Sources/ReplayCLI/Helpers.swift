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
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

    for case let url as URL in enumerator {
        guard url.pathExtension == "swift" else { continue }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }

        let range = NSRange(contents.startIndex ..< contents.endIndex, in: contents)
        let matches = regex.matches(in: contents, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges > 1,
                let nameRange = Range(match.range(at: 1), in: contents)
            else { continue }
            names.insert(String(contents[nameRange]))
        }
    }

    return names
}
