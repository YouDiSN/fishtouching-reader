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
    static func run() throws {
        let paragraphs = ["正文第一行。", "正文第二行。", "下一段。"]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = Vault(root: root)
        try vault.configure(password: "test-pass-123")
        let id = try vault.saveText(title: "测试文章", paragraphs: paragraphs, sourceURL: "")
        try check(UUID(uuidString: id) != nil, "UUID filename")
        try vault.saveProgress(ReadingProgress(paragraph: 1, fraction: 0.5, updatedAt: Date()), for: id)
        vault.lock()
        try check((try? vault.load(id)) == nil, "locked book")
        try check((try? vault.unlock(password: "wrong")) == nil, "wrong password rejected")
        try vault.unlock(password: "test-pass-123")
        try check(try vault.load(id).paragraphs == paragraphs, "book round trip")
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
        let textID = try publicText.list()[0].id
        try check(try publicText.load(textID).count == 2, "public TXT")
        try publicText.saveProgress(ReadingProgress(paragraph: 1, fraction: 0, updatedAt: Date()), for: textID)
        try publicPDF.removeFromLibrary(publicItem.id)
        try check(try publicPDF.list().isEmpty, "removed PDF hidden")
        try check(!FileManager.default.fileExists(atPath: publicPDF.fileURL(for: publicItem.id).path), "PDF copy deleted")
        try check(try publicPDF.loadProgress(for: publicItem.id) == nil, "PDF progress deleted")
        try check(FileManager.default.fileExists(atPath: sourcePDF.path), "original PDF retained")
        try publicText.removeFromLibrary(textID)
        try check(try publicText.list().isEmpty, "removed TXT hidden")
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("public-texts/\(textID).txt").path), "TXT copy deleted")
        try check(try publicText.progress(textID) == nil, "TXT progress deleted")
        try check(FileManager.default.fileExists(atPath: sourceTXT.path), "original TXT retained")
        try vault.removeFromLibrary(id)
        try vault.removeFromLibrary(pdfID)
        try check(try vault.list().isEmpty, "removed secure books hidden")
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("secure-data/\(id).bin").path), "secure text copy deleted")
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("secure-data/\(id).progress").path), "secure text progress deleted")
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("secure-data/\(pdfID).bin").path), "secure PDF copy deleted")
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("secure-data/\(pdfID).progress").path), "secure PDF progress deleted")
        let shortPasswordVault = Vault(root: root.appendingPathComponent("four-character-password"))
        try shortPasswordVault.configure(password: "1234")
        shortPasswordVault.lock()
        try shortPasswordVault.unlock(password: "1234")
        try shortPasswordVault.changePassword(old: "1234", new: "5678")
        shortPasswordVault.lock()
        try shortPasswordVault.unlock(password: "5678")
        try check((try? shortPasswordVault.changePassword(old: "5678", new: "123")) == nil,
                  "password shorter than four rejected")
        print("Self-test passed: password, encryption, TXT/PDF, progress, removal")
    }
    private static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        if try !condition() { throw NSError(domain: "SelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed: \(name)"]) }
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
