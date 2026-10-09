import Foundation
import PDFKit

struct LocalPDF: Codable {
    let id: String
    let title: String
    let importedAt: Date
    let pageCount: Int?
}

struct PDFReadingProgress: Codable {
    let pageIndex: Int
    let x: Double
    let y: Double
    let fraction: Double?
    let updatedAt: Date?

    init(pageIndex: Int, x: Double, y: Double, fraction: Double? = nil, updatedAt: Date? = nil) {
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
        self.fraction = fraction
        self.updatedAt = updatedAt
    }
}

final class PDFLibrary {
    private let root: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var pageCountCache: [String: Int] = [:]

    init(root: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = root ?? base.appendingPathComponent("LocalLibrary/public-pdfs", isDirectory: true)
    }

    private var catalogURL: URL { root.appendingPathComponent("catalog.json") }
    private var progressURL: URL { root.appendingPathComponent("progress.json") }

    private func progressMap() throws -> [String: PDFReadingProgress] {
        guard FileManager.default.fileExists(atPath: progressURL.path) else { return [:] }
        let stored = try decoder.decode([String: PDFReadingProgress].self, from: Data(contentsOf: progressURL))
        let fileDate = (try? FileManager.default.attributesOfItem(atPath: progressURL.path)[.modificationDate]) as? Date
        return stored.mapValues { progress in
            PDFReadingProgress(pageIndex: progress.pageIndex, x: progress.x, y: progress.y,
                               fraction: progress.fraction, updatedAt: progress.updatedAt ?? fileDate)
        }
    }

    func listWithProgress() throws -> [(pdf: LocalPDF, progress: PDFReadingProgress?, pageCount: Int)] {
        let progress = try progressMap()
        return try list().map { pdf in
            let count: Int
            if let stored = pdf.pageCount { count = stored }
            else if let cached = pageCountCache[pdf.id] { count = cached }
            else {
                count = PDFDocument(url: fileURL(for: pdf.id))?.pageCount ?? 0
                pageCountCache[pdf.id] = count
            }
            return (pdf: pdf, progress: progress[pdf.id], pageCount: count)
        }
    }

    func loadProgress(for id: String) throws -> PDFReadingProgress? {
        try progressMap()[id]
    }

    func saveProgress(_ position: PDFReadingProgress, for id: String) throws {
        guard try list().contains(where: { $0.id == id }) else { return }
        var progress = try progressMap()
        progress[id] = PDFReadingProgress(pageIndex: position.pageIndex, x: position.x, y: position.y,
                                          fraction: position.fraction, updatedAt: Date())
        try encoder.encode(progress).write(to: progressURL, options: .atomic)
    }

    func list() throws -> [LocalPDF] {
        guard FileManager.default.fileExists(atPath: catalogURL.path) else { return [] }
        return try decoder.decode([LocalPDF].self, from: Data(contentsOf: catalogURL))
            .filter { FileManager.default.fileExists(atPath: fileURL(for: $0.id).path) }
            .sorted { $0.importedAt > $1.importedAt }
    }

    @discardableResult func importFile(_ source: URL) throws -> LocalPDF {
        guard source.pathExtension.lowercased() == "pdf" else {
            throw NSError(domain: "PDFLibrary", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "请选择 PDF 文件。"])
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pdf = LocalPDF(id: UUID().uuidString, title: source.deletingPathExtension().lastPathComponent,
                           importedAt: Date(), pageCount: PDFDocument(url: source)?.pageCount)
        try FileManager.default.copyItem(at: source, to: fileURL(for: pdf.id))
        var items = try list()
        items.append(pdf)
        try encoder.encode(items).write(to: catalogURL, options: .atomic)
        return pdf
    }

    func fileURL(for id: String) -> URL {
        root.appendingPathComponent(id).appendingPathExtension("pdf")
    }
}
