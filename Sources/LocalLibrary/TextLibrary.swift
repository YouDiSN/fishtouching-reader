import Foundation
import CoreFoundation

enum PlainTextDecoder {
    static func decode(_ data: Data) -> String? {
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632)))
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: gb18030)
    }
}

struct PublicText: Codable {
    let id: String
    let title: String
    let importedAt: Date
    let paragraphCount: Int
    let wordCount: Int
}
final class TextLibrary {
    private let root: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    init(root: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = root ?? base.appendingPathComponent("LocalLibrary/public-texts", isDirectory: true)
    }
    private var catalogURL: URL { root.appendingPathComponent("catalog.json") }
    private var progressURL: URL { root.appendingPathComponent("progress.json") }
    func list() throws -> [PublicText] {
        guard FileManager.default.fileExists(atPath: catalogURL.path) else { return [] }
        return try decoder.decode([PublicText].self, from: Data(contentsOf: catalogURL))
    }
    private func url(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw VaultFailure.badData }
        return root.appendingPathComponent(id).appendingPathExtension("txt")
    }
    func importFile(_ source: URL) throws {
        let data = try Data(contentsOf: source)
        guard let text = PlainTextDecoder.decode(data) else { throw VaultFailure.badData }
        let paragraphs = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let count = paragraphs.reduce(0) { $0 + $1.unicodeScalars.reduce(0) { $0 + (CharacterSet.alphanumerics.contains($1) ? 1 : 0) } }
        let item = PublicText(id: UUID().uuidString, title: source.deletingPathExtension().lastPathComponent,
                              importedAt: Date(), paragraphCount: paragraphs.count, wordCount: count)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: url(item.id), options: .atomic)
        var items = try list(); items.append(item)
        try encoder.encode(items).write(to: catalogURL, options: .atomic)
    }
    func load(_ id: String) throws -> [String] {
        let data = try Data(contentsOf: url(id))
        guard let text = PlainTextDecoder.decode(data) else { throw VaultFailure.badData }
        return text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private func progressMap() throws -> [String: ReadingProgress] {
        guard FileManager.default.fileExists(atPath: progressURL.path) else { return [:] }
        return try decoder.decode([String: ReadingProgress].self, from: Data(contentsOf: progressURL))
    }
    func progress(_ id: String) throws -> ReadingProgress? { try progressMap()[id] }
    func saveProgress(_ progress: ReadingProgress, for id: String) throws {
        var map = try progressMap(); map[id] = progress
        try encoder.encode(map).write(to: progressURL, options: .atomic)
    }
}
