import Foundation
import CryptoKit
import Security

@_silgen_name("sodium_init") private func sodiumInit() -> Int32
@_silgen_name("crypto_pwhash") private func sodiumPwhash(_ output: UnsafeMutablePointer<UInt8>, _ outputLength: UInt64, _ password: UnsafePointer<CChar>, _ passwordLength: UInt64, _ salt: UnsafePointer<UInt8>, _ operations: UInt64, _ memory: Int, _ algorithm: Int32) -> Int32

struct StoredBook: Codable {
    let sourceURL: String
    let encodedTitle: String
    let originalTitle: String
    let paragraphs: [String]
    let importedAt: Date
}
struct ReadingProgress: Codable {
    var paragraph: Int
    var fraction: Double
    var updatedAt: Date
}
struct BookListing {
    let id: String
    let sourceURL: String
    let encodedTitle: String
    let host: String
    let paragraphCount: Int
    let wordCount: Int
    let progress: ReadingProgress?
    let kind: String
    let pageCount: Int
}
private struct VaultConfig: Codable {
    let version: Int
    let salt: Data?
    let wrappedKey: Data?
    let operations: UInt64?
    let memory: Int?
}
private struct CatalogEntry: Codable {
    let id: String
    let title: String
    let sourceURL: String
    let kind: String
    let importedAt: Date
    let paragraphCount: Int
    let wordCount: Int
    let pageCount: Int
}
private struct SecureCatalog: Codable { var entries: [CatalogEntry] }
enum VaultFailure: LocalizedError {
    case alreadyConfigured, notConfigured, locked, badData, keychain(OSStatus), legacyVault, wrongPassword, invalidPassword
    var errorDescription: String? {
        switch self {
        case .alreadyConfigured: return "书库已经创建。"
        case .notConfigured: return "请先设置密码。"
        case .locked: return "书库已锁定。"
        case .badData: return "书库文件损坏或无法解密。"
        case .keychain(let status): return "无法读取 macOS 钥匙串（错误码 \(status)）。"
        case .legacyVault: return "旧版书库无法迁移。"
        case .wrongPassword: return "密码不正确。"
        case .invalidPassword: return "密码至少需要 4 个字符。"
        }
    }
}
final class Vault {
    let root: URL
    private var key: SymmetricKey?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let service = "local.library.reader.vault"
    private let account = "master-key-v2"
    private var configURL: URL { root.appendingPathComponent("vault.json") }
    private var keyURL: URL { root.appendingPathComponent("vault.key") }
    private var oldBooksRoot: URL { root.appendingPathComponent("books", isDirectory: true) }
    private var dataRoot: URL { root.appendingPathComponent("secure-data", isDirectory: true) }
    private var catalogURL: URL { root.appendingPathComponent("secure-catalog.bin") }

    init(root: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = root ?? base.appendingPathComponent("LocalLibrary", isDirectory: true)
        encoder.outputFormatting = [.sortedKeys]
    }
    var isConfigured: Bool { (try? readConfig().version) == 4 }
    var needsSetup: Bool { !isConfigured }
    var isUnlocked: Bool { key != nil }
    private func readConfig() throws -> VaultConfig { try decoder.decode(VaultConfig.self, from: Data(contentsOf: configURL)) }
    private func random(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        guard bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }) == errSecSuccess else { throw VaultFailure.badData }
        return bytes
    }
    private func derive(_ password: String, salt: Data, operations: UInt64, memory: Int) throws -> SymmetricKey {
        guard sodiumInit() >= 0 else { throw VaultFailure.badData }
        var output = Data(count: 32)
        let result = output.withUnsafeMutableBytes { result in
            salt.withUnsafeBytes { saltBytes in
                password.withCString { chars in
                    sodiumPwhash(result.bindMemory(to: UInt8.self).baseAddress!, 32, chars,
                                 UInt64(password.utf8.count), saltBytes.bindMemory(to: UInt8.self).baseAddress!,
                                 operations, memory, 2)
                }
            }
        }
        guard result == 0 else { throw VaultFailure.badData }
        return SymmetricKey(data: output)
    }
    private func config(password: String, master: SymmetricKey) throws -> VaultConfig {
        let salt = try random(16)
        let operations: UInt64 = 3
        let memory = 64 * 1024 * 1024
        let wrapping = try derive(password, salt: salt, operations: operations, memory: memory)
        let raw = master.withUnsafeBytes { Data($0) }
        return VaultConfig(version: 4, salt: salt, wrappedKey: try seal(raw, with: wrapping), operations: operations, memory: memory)
    }
    func configure(password: String) throws {
        guard password.count >= 4 else { throw VaultFailure.invalidPassword }
        guard !isConfigured else { throw VaultFailure.alreadyConfigured }
        if FileManager.default.fileExists(atPath: configURL.path) {
            guard let version = try? readConfig().version, version == 2 || version == 3 else { throw VaultFailure.legacyVault }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let master = SymmetricKey(data: try random(32))
        let newConfig = try config(password: password, master: master)
        // Finish all decryption and writes before publishing the new config.
        if FileManager.default.fileExists(atPath: oldBooksRoot.path) {
            try migrateLegacy(using: master)
        } else {
            try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
            try seal(encoder.encode(SecureCatalog(entries: [])), with: master).write(to: catalogURL, options: .atomic)
        }
        try encoder.encode(newConfig).write(to: configURL, options: .atomic)
        key = master
        try? FileManager.default.removeItem(at: keyURL)
        try? FileManager.default.removeItem(at: oldBooksRoot)
    }
    func unlock(password: String) throws {
        guard isConfigured else { throw VaultFailure.notConfigured }
        let config = try readConfig()
        guard let salt = config.salt, let wrapped = config.wrappedKey,
              let operations = config.operations, let memory = config.memory else { throw VaultFailure.badData }
        let wrapping = try derive(password, salt: salt, operations: operations, memory: memory)
        let raw: Data
        do { raw = try open(wrapped, with: wrapping) } catch { throw VaultFailure.wrongPassword }
        guard raw.count == 32 else { throw VaultFailure.badData }
        key = SymmetricKey(data: raw)
        _ = try catalog()
        try? FileManager.default.removeItem(at: keyURL)
        try? FileManager.default.removeItem(at: oldBooksRoot)
    }
    func changePassword(old: String, new: String) throws {
        guard new.count >= 4 else { throw VaultFailure.invalidPassword }
        try unlock(password: old)
        guard let key else { throw VaultFailure.locked }
        try encoder.encode(config(password: new, master: key)).write(to: configURL, options: .atomic)
    }
    func lock() { key = nil }
    private func catalog() throws -> SecureCatalog {
        guard let key else { throw VaultFailure.locked }
        return try decoder.decode(SecureCatalog.self, from: open(Data(contentsOf: catalogURL), with: key))
    }
    private func writeCatalog(_ value: SecureCatalog) throws {
        guard let key else { throw VaultFailure.locked }
        try seal(encoder.encode(value), with: key).write(to: catalogURL, options: .atomic)
    }
    private func dataURL(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw VaultFailure.badData }
        return dataRoot.appendingPathComponent(id).appendingPathExtension("bin")
    }
    private func progressURL(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw VaultFailure.badData }
        return dataRoot.appendingPathComponent(id).appendingPathExtension("progress")
    }
    private func countWords(_ paragraphs: [String]) -> Int {
        paragraphs.reduce(0) { total, p in total + p.unicodeScalars.reduce(0) { $0 + (CharacterSet.alphanumerics.contains($1) ? 1 : 0) } }
    }
    private func insert(data: Data, title: String, sourceURL: String, kind: String,
                        importedAt: Date, paragraphCount: Int, wordCount: Int, pageCount: Int) throws -> String {
        guard let key else { throw VaultFailure.locked }
        let id = UUID().uuidString
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try seal(data, with: key).write(to: dataURL(id), options: .atomic)
        var entries = try catalog()
        entries.entries.append(CatalogEntry(id: id, title: title, sourceURL: sourceURL, kind: kind,
                                            importedAt: importedAt, paragraphCount: paragraphCount,
                                            wordCount: wordCount, pageCount: pageCount))
        try writeCatalog(entries)
        return id
    }
    func save(_ imported: ImportedBook) throws -> String {
        let book = StoredBook(sourceURL: imported.sourceURL, encodedTitle: imported.encodedTitle,
                              originalTitle: imported.originalTitle, paragraphs: imported.paragraphs, importedAt: Date())
        return try insert(data: encoder.encode(book), title: book.originalTitle, sourceURL: book.sourceURL,
                          kind: "text", importedAt: book.importedAt, paragraphCount: book.paragraphs.count,
                          wordCount: countWords(book.paragraphs), pageCount: 0)
    }
    func saveText(title: String, paragraphs: [String], sourceURL: String) throws -> String {
        try save(ImportedBook(sourceURL: sourceURL, encodedTitle: title, originalTitle: title, paragraphs: paragraphs))
    }
    func savePDF(data: Data, title: String, pageCount: Int) throws -> String {
        try insert(data: data, title: title, sourceURL: "", kind: "pdf", importedAt: Date(),
                   paragraphCount: 0, wordCount: 0, pageCount: pageCount)
    }
    func loadPDF(_ id: String) throws -> Data {
        guard let key else { throw VaultFailure.locked }
        guard try catalog().entries.contains(where: { $0.id == id && $0.kind == "pdf" }) else { throw VaultFailure.badData }
        return try open(Data(contentsOf: dataURL(id)), with: key)
    }
    func load(_ id: String) throws -> StoredBook {
        guard let key else { throw VaultFailure.locked }
        guard try catalog().entries.contains(where: { $0.id == id && $0.kind == "text" }) else { throw VaultFailure.badData }
        return try decoder.decode(StoredBook.self, from: open(Data(contentsOf: dataURL(id)), with: key))
    }
    func list() throws -> [BookListing] {
        try catalog().entries.map { entry in
            BookListing(id: entry.id, sourceURL: entry.sourceURL, encodedTitle: entry.title,
                        host: URL(string: entry.sourceURL)?.host ?? (entry.kind == "pdf" ? "PDF" : "本地文件"),
                        paragraphCount: entry.paragraphCount, wordCount: entry.wordCount,
                        progress: entry.kind == "text" ? try loadProgress(entry.id) : nil,
                        kind: entry.kind, pageCount: entry.pageCount)
        }.sorted { ($0.progress?.updatedAt ?? .distantPast) > ($1.progress?.updatedAt ?? .distantPast) }
    }
    func removeFromLibrary(_ id: String) throws {
        var value = try catalog()
        guard let index = value.entries.firstIndex(where: { $0.id == id }) else { throw VaultFailure.badData }
        value.entries.remove(at: index)
        try writeCatalog(value)
        let file = try dataURL(id)
        let progress = try progressURL(id)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        if FileManager.default.fileExists(atPath: progress.path) { try FileManager.default.removeItem(at: progress) }
    }
    func saveProgress(_ progress: ReadingProgress, for id: String) throws {
        guard let key else { throw VaultFailure.locked }
        try seal(encoder.encode(progress), with: key).write(to: progressURL(id), options: .atomic)
    }
    func loadProgress(_ id: String) throws -> ReadingProgress? {
        guard let key else { throw VaultFailure.locked }
        let url = try progressURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(ReadingProgress.self, from: open(Data(contentsOf: url), with: key))
    }
    func savePDFProgress(_ progress: PDFReadingProgress, for id: String) throws {
        guard let key else { throw VaultFailure.locked }
        try seal(encoder.encode(progress), with: key).write(to: progressURL(id), options: .atomic)
    }
    func loadPDFProgress(_ id: String) throws -> PDFReadingProgress? {
        guard let key else { throw VaultFailure.locked }
        let url = try progressURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(PDFReadingProgress.self, from: open(Data(contentsOf: url), with: key))
    }
    private func migrateLegacy(using master: SymmetricKey) throws {
        let legacy: SymmetricKey
        if FileManager.default.fileExists(atPath: keyURL.path) {
            let raw = try Data(contentsOf: keyURL)
            guard raw.count == 32 else { throw VaultFailure.badData }
            legacy = SymmetricKey(data: raw)
        } else {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                        kSecAttrService as String: service, kSecAttrAccount as String: account,
                                        kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            guard status == errSecSuccess, let raw = value as? Data, raw.count == 32 else { throw VaultFailure.keychain(status) }
            legacy = SymmetricKey(data: raw)
        }
        let fm = FileManager.default
        let files = (fm.enumerator(at: oldBooksRoot, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "book" }
        let stage = root.appendingPathComponent(".secure-stage-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        var entries: [CatalogEntry] = []
        do {
            for url in files {
                let book = try decoder.decode(StoredBook.self, from: open(Data(contentsOf: url), with: legacy))
                let id = UUID().uuidString
                try seal(encoder.encode(book), with: master).write(to: stage.appendingPathComponent(id + ".bin"), options: .atomic)
                let progressURL = url.deletingPathExtension().appendingPathExtension("progress")
                if fm.fileExists(atPath: progressURL.path) {
                    let progress = try open(Data(contentsOf: progressURL), with: legacy)
                    try seal(progress, with: master).write(to: stage.appendingPathComponent(id + ".progress"), options: .atomic)
                }
                entries.append(CatalogEntry(id: id, title: book.originalTitle, sourceURL: book.sourceURL,
                                            kind: "text", importedAt: book.importedAt,
                                            paragraphCount: book.paragraphs.count,
                                            wordCount: countWords(book.paragraphs), pageCount: 0))
            }
            let catalogData = try seal(encoder.encode(SecureCatalog(entries: entries)), with: master)
            let stagedCatalog = root.appendingPathComponent(".secure-catalog-\(UUID().uuidString)")
            try catalogData.write(to: stagedCatalog, options: .atomic)
            if fm.fileExists(atPath: dataRoot.path) { try fm.removeItem(at: dataRoot) }
            try fm.moveItem(at: stage, to: dataRoot)
            if fm.fileExists(atPath: catalogURL.path) { try fm.removeItem(at: catalogURL) }
            try fm.moveItem(at: stagedCatalog, to: catalogURL)
        } catch {
            try? fm.removeItem(at: stage)
            throw error
        }
    }
    private func seal(_ data: Data, with key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw VaultFailure.badData }
        return combined
    }
    private func open(_ data: Data, with key: SymmetricKey) throws -> Data {
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key) }
        catch { throw VaultFailure.badData }
    }
}
