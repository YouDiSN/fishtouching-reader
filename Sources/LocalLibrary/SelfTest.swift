import Foundation
import CryptoKit
import Security
import PDFKit
import AppKit

enum SelfTest {
    static func verifyMigration(source: URL) throws {
        let expectedBooks = (FileManager.default.enumerator(at: source.appendingPathComponent("books"), includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "book" }.count
        let expectedProgress = (FileManager.default.enumerator(at: source.appendingPathComponent("books"), includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "progress" }.count
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("library-migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
        let vault = Vault(root: destination)
        try vault.configure(password: "migration-test-password")
        try check(vault.list().count == expectedBooks, "migrated book count")
        let progressCount = try vault.list().filter { $0.progress != nil }.count
        try check(progressCount == expectedProgress, "migrated progress count")
        vault.lock()
        try vault.unlock(password: "migration-test-password")
        try check(vault.list().count == expectedBooks, "reopened migrated books")
        let files = (FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
        try check(!files.contains(where: { $0.lastPathComponent == "vault.key" || $0.pathExtension == "book" }), "legacy files removed")
        print("Migration verified: \(expectedBooks) books, \(expectedProgress) progress records")
    }
    static func run(live: Bool) throws {
        let html = "<html><h1 class='wp-block-post-title'>测试文章</h1><div class='entry-content wp-block-post-content'><p class='wp-block-paragraph'>正文第一行。<br>正文第二行。</p><p class='wp-block-paragraph'>下一段。</p></div></html>"
        let source = URL(string: "https://example.wordpress.com/2024/01/01/test/")!
        let imported = try WordPressImporter.extract(html: html, sourceURL: source)
        try check(imported.paragraphs.count == 3, "extraction")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = Vault(root: root)
        try vault.configure(password: "test-pass-123")
        let id = try vault.save(imported)
        try check(UUID(uuidString: id) != nil, "UUID filename")
        try vault.saveProgress(ReadingProgress(paragraph: 1, fraction: 0.5, updatedAt: Date()), for: id)
        vault.lock()
        try check((try? vault.load(id)) == nil, "locked book")
        try check((try? vault.unlock(password: "wrong")) == nil, "wrong password rejected")
        try vault.unlock(password: "test-pass-123")
        try check(try vault.load(id).paragraphs == imported.paragraphs, "book round trip")
        try check(try vault.loadProgress(id)?.paragraph == 1, "progress round trip")
        try check(try vault.list().first?.encodedTitle == "测试文章", "encrypted catalog title")
        try vault.changePassword(old: "test-pass-123", new: "new-pass-123")
        vault.lock()
        try check((try? vault.unlock(password: "test-pass-123")) == nil, "old password rejected")
        try vault.unlock(password: "new-pass-123")
        try check(try vault.load(id).paragraphs.count == 3, "new password round trip")
        let disk = try Data(contentsOf: root.appendingPathComponent("secure-data/\(id).bin"))
        try check(!disk.contains(Data("正文第一行".utf8)), "encrypted body")
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("vault.key").path), "no raw key")
        let pdf = PDFDocument()
        let image = NSImage(size: NSSize(width: 30, height: 30))
        image.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 30, height: 30).fill(); image.unlockFocus()
        guard let page = PDFPage(image: image) else { throw VaultFailure.badData }
        pdf.insert(page, at: 0)
        guard let pdfData = pdf.dataRepresentation() else { throw VaultFailure.badData }
        let pdfID = try vault.savePDF(data: pdfData, title: "隐私 PDF", pageCount: 1)
        try vault.savePDFProgress(PDFReadingProgress(pageIndex: 0, x: 5, y: 6), for: pdfID)
        try check(try vault.loadPDF(pdfID) == pdfData, "encrypted PDF")
        try check(try vault.loadPDFProgress(pdfID)?.x == 5, "PDF progress")
        try check(try vault.list().count == 2, "mixed catalog")
        let sourcePDF = root.appendingPathComponent("sample.pdf")
        try pdfData.write(to: sourcePDF)
        let publicPDF = PDFLibrary(root: root.appendingPathComponent("public-pdfs"))
        let publicItem = try publicPDF.importFile(sourcePDF)
        try publicPDF.saveProgress(PDFReadingProgress(pageIndex: 0, x: 10, y: 20), for: publicItem.id)
        try check(try publicPDF.loadProgress(for: publicItem.id)?.x == 10, "public PDF progress")
        let sourceTXT = root.appendingPathComponent("sample.txt")
        try Data("一行\n二行".utf8).write(to: sourceTXT)
        let publicText = TextLibrary(root: root.appendingPathComponent("public-texts"))
        try publicText.importFile(sourceTXT)
        try check(try publicText.load(publicText.list()[0].id).count == 2, "public TXT")
        let shortPasswordVault = Vault(root: root.appendingPathComponent("four-character-password"))
        try shortPasswordVault.configure(password: "1234")
        shortPasswordVault.lock()
        try shortPasswordVault.unlock(password: "1234")
        try shortPasswordVault.changePassword(old: "1234", new: "5678")
        shortPasswordVault.lock()
        try shortPasswordVault.unlock(password: "5678")
        try check((try? shortPasswordVault.changePassword(old: "5678", new: "123")) == nil,
                  "password shorter than four rejected")
        print("Self-test passed: extraction, password, encryption, TXT/PDF, progress")
        if live { try runLive() }
    }
    private static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        if try !condition() { throw NSError(domain: "SelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed: \(name)"]) }
    }
    private static func runLive() throws {
        let url = URL(string: "https://example.invalid/removed")!
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<ImportedBook, Error>?
        WordPressImporter.fetch(url) { result = $0; semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 45) == .success, let book = try result?.get() else { throw ImportFailure.badResponse }
        try check(book.paragraphs.count > 8_000, "live import")
        print("Live import passed: \(book.paragraphs.count) paragraphs")
        let coolURL = URL(string: "https://example.invalid/removed")!
        var coolHTML: Result<String, Error>?
        let second = DispatchSemaphore(value: 0)
        WordPressImporter.fetchHTML(coolURL) { coolHTML = $0; second.signal() }
        guard second.wait(timeout: .now() + 45) == .success, let html = try coolHTML?.get() else { throw ImportFailure.badResponse }
        let links = try WordPressImporter.indexLinks(html: html, sourceURL: coolURL)
        try check(links.count >= 20, "Cool18 index links")
        let excerpt = try WordPressImporter.extract(html: html, sourceURL: coolURL)
        try check(excerpt.paragraphs.count > 20, "Cool18 PRE extraction")
        print("Cool18 verified: \(links.count) links, \(excerpt.paragraphs.count) paragraphs")
    }
    static func probeKeychain() throws {
        let service = "local.library.reader.probe.\(UUID().uuidString)"
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "temporary"]
        var add = base; add[kSecValueData as String] = Data([3, 7, 11])
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultFailure.keychain(status) }
        defer { SecItemDelete(base as CFDictionary) }
        print("Login Keychain probe passed")
    }
}
