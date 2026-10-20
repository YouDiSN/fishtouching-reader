import CryptoKit
import AppKit
import WebKit
import Carbon
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Sparkle

private final class PointingHandButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private enum AppDefaults {
    static let displayName = "FishTouching Reader"
    static let iconID = "fish"
}
private enum VaultPolicy { static let maximum = 2 }

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var updaterController: SPUStandardUpdaterController?
    private let primaryVault = Vault()
    private lazy var vaults: [Vault] = [primaryVault] + (1..<VaultPolicy.maximum).map {
        Vault(root: primaryVault.root.appendingPathComponent("spaces/\($0 + 1)", isDirectory: true))
    }
    private var activeVaultIndex = 0
    private var vault: Vault { vaults[activeVaultIndex] }
    private var settingsVaultIndex: Int? = nil
    private var secureResumeVaultIndex = 0
    private let pdfLibrary = PDFLibrary()
    private let textLibrary = TextLibrary()
    private let importPlugins = ImportPluginRegistry()
    private var webJob: WebDownloadJob?
    private var webPreview: [String:Any]?
    private var window: NSWindow!
    private var webView: WKWebView!
    private var aboutWindowController: AboutWindowController?
    private var settingsVisible = false
    private var settingsOpening = false
    private var nameRestartScheduled = false
    private var pdfContainer: NSView!
    private var pdfView: PDFView!
    private var pdfBackButton: NSButton!
    private var pdfPreviousButton: NSButton!
    private var pdfNextButton: NSButton!
    private var pdfPageField: NSTextField!
    private var pdfPageLabel: NSTextField!
    private var pdfPercentLabel: NSTextField!
    private var pdfOutlineButton: NSPopUpButton!
    private var pdfReturnButton: NSButton!
    private var pdfJumpOrigin: PDFDestination?
    private var pdfOutlineDestinations: [PDFDestination] = []
    private var currentPDFID: String?
    private var currentPDFIsCover = false
    private var currentPDFIsSecure = false
    private var pdfScrollView: NSScrollView?
    private var pdfProgressWorkItem: DispatchWorkItem?
    private var currentBookID: String?
    private var secureResumeID: String?
    private var currentTab = "normal"
    private var secureTransitioning = false
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeyRegistrationStatus: OSStatus = -1
    private var lastHotKeyAt = Date.distantPast
    private var statusItem: NSStatusItem?
    private let presetIconIDs: Set<String> = ["book", "fish", "night", "leaf", "coffee", "star", "pencil", "music", "sunrise", "cloud"]
    private var displayName: String { UserDefaults.standard.string(forKey: "displayName") ?? AppDefaults.displayName }
    private var customIconURL: URL { primaryVault.root.appendingPathComponent("appearance-icon.png") }
    private var activeIconID: String {
        if let saved = UserDefaults.standard.string(forKey: "appearanceIconID"),
           presetIconIDs.contains(saved) || (saved == "custom" && FileManager.default.fileExists(atPath: customIconURL.path)) {
            return saved
        }
        return FileManager.default.fileExists(atPath: customIconURL.path) ? "custom" : AppDefaults.iconID
    }
    private func iconURL(for id: String) -> URL? {
        if id == "custom" { return customIconURL }
        return Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "Icons")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ProcessInfo.processInfo.processName = displayName
        if let iconURL = iconURL(for: activeIconID) ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = icon }
        let config = WKWebViewConfiguration()
        let messages = WKUserContentController()
        messages.add(self, name: "app")
        messages.add(self, name: "settings")
        config.userContentController = messages
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 740),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = displayName
        window.center()
        window.minSize = NSSize(width: 680, height: 520)
        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        webView.frame = content.bounds
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)
        window.contentView = content
        buildPDFView(in: content)
        window.delegate = self
        if Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil {
            updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        buildMenu()
        buildStatusItem()
        installHotKey()
        NotificationCenter.default.addObserver(self, selector: #selector(onLostFocus),
                                               name: NSApplication.willResignActiveNotification, object: NSApp)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onOtherAppActivated),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        let uiURL = Bundle.main.url(forResource: "index", withExtension: "html")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/index.html")
        webView.loadFileURL(uiURL, allowingReadAccessTo: uiURL.deletingLastPathComponent())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        savePDFProgress()
        if !nameRestartScheduled, let pending = UserDefaults.standard.string(forKey: "pendingDisplayName") {
            try? scheduleNameUpdate(pending, reopen: false)
        }
        vaults.forEach { $0.lock() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if primaryVault.needsSetup { send(["type": "setup", "iconID": activeIconID]); return }
        if currentTab == "secure" {
            vault.lock()
            showLocked()
        } else { showNormalLibrary() }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let data = message.body as? [String: Any], let action = data["action"] as? String else { return }
        if handleReadingAppearance(action, data: data, source: message.webView) { return }
        if message.name == "settings" { handleSettingsAction(action, data: data); return }
        if ["selectNormal", "selectSecure", "unlock", "lock", "settings", "read", "openPDF", "library", "toggleImportPlugin", "removeImportPlugin"].contains(action) { cancelWebImport() }
        switch action {
        case "installWebPlugin": installWebPlugin(data)
        case "previewWebsite": previewWebsite(data)
        case "importWebsite": importWebsite(data)
        case "cancelWebImport": cancelWebImport()
        case "retry": currentTab == "secure" ? showLocked() : showNormalLibrary()
        case "selectNormal": selectNormal()
        case "selectSecure": selectSecure()
        case "unlock": unlockSecure(data["password"] as? String ?? "")
        case "setup": finishSetup(data)
        case "settings": showSettings()
        case "chooseIcon": chooseIcon()
        case "selectIcon": choosePresetIcon(data["id"] as? String ?? "")
        case "listImportPlugins": sendImportPlugins()
        case "installImportPlugin": installImportPlugin()
        case "toggleImportPlugin":
            do { try importPlugins.setEnabled(data["id"] as? String ?? "", enabled: data["enabled"] as? Bool ?? false); sendImportPlugins() }
            catch { sendImportPlugins(error: error.localizedDescription) }
        case "removeImportPlugin": removeImportPlugin(data["id"] as? String ?? "")
        case "importLocal": importLocal()
        case "lock": secureLock()
        case "importPDF": importLocal()
        case "openPDF":
            if let id = data["id"] as? String { openPDF(id) }
        case "library":
            currentBookID = nil
            if currentTab == "secure" { secureResumeID = nil; sendLibrary() }
            else { showNormalLibrary() }
        case "read":
            guard let id = data["id"] as? String else { return }
            if currentTab == "secure" { showBook(id) } else { showNormalText(id) }
        case "exportText":
            if let id = data["id"] as? String { exportText(id) }
        case "exportEPUB":
            if let id = data["id"] as? String { exportEPUB(id) }
        case "removeBook":
            guard let id = data["id"] as? String else { return }
            removeBook(id, kind: data["kind"] as? String ?? "")
        case "removeRecent":
            guard let id = data["id"] as? String else { return }
            removeRecent(id, kind: data["kind"] as? String ?? "")
        case "transferBook":
            if let id = data["id"] as? String, let password = data["password"] as? String {
                transferBook(id, password: password)
            }
        case "progress":
            guard let id = currentBookID,
                  let paragraph = data["paragraph"] as? Int,
                  let fraction = data["fraction"] as? Double else { return }
            let progress = ReadingProgress(paragraph: max(0, paragraph),
                                           fraction: min(1, max(0, fraction)), updatedAt: Date())
            if currentTab == "secure", vault.isUnlocked { try? vault.saveProgress(progress, for: id) }
            else if currentTab == "normal" { try? textLibrary.saveProgress(progress, for: id) }
        case "hide": hideWindow()
        default: break
        }
    }

    private func showBook(_ id: String) {
        do {
            if try vault.list().contains(where: { $0.id == id && $0.kind == "pdf" }) {
                openSecurePDF(id); return
            }
            let book = try vault.load(id)
            let progress = try vault.loadProgress(id)
            currentBookID = id
            secureResumeID = id
            secureResumeVaultIndex = activeVaultIndex
            send(["type": "book", "id": id, "encodedTitle": book.encodedTitle,
                  "paragraphs": book.paragraphs, "hasEPUB": book.epubArchive != nil,
                  "paragraph": progress?.paragraph ?? 0,
                  "fraction": progress?.fraction ?? 0])
        } catch { sendError(error.localizedDescription, context: "library") }
    }

    private func exportText(_ id: String) {
        guard currentTab == "secure", vault.isUnlocked, currentBookID == id else { return }
        do {
            guard let item = try vault.list().first(where: { $0.id == id && $0.kind == "text" }) else { return }
            let title = (item.encodedTitle.removingPercentEncoding ?? item.encodedTitle)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .components(separatedBy: .newlines).joined(separator: " ")
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "\(title).txt"
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .OK, let url = panel.url,
                      self.currentTab == "secure", self.vault.isUnlocked,
                      self.currentBookID == id else { return }
                do {
                    let book = try self.vault.load(id)
                    try book.paragraphs.joined(separator: "\n\n").write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    self.sendError(error.localizedDescription, context: "book")
                }
            }
        } catch { sendError(error.localizedDescription, context: "book") }
    }
    private func exportEPUB(_ id: String) {
        guard currentTab == "secure", vault.isUnlocked, currentBookID == id else { return }
        do {
            let book = try vault.load(id)
            guard book.epubArchive != nil else { return }
            let title = book.originalTitle.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .components(separatedBy: .newlines).joined(separator: " ")
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]
            panel.nameFieldStringValue = "\(title).epub"
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .OK, let url = panel.url,
                      self.currentTab == "secure", self.vault.isUnlocked,
                      self.currentBookID == id else { return }
                do {
                    guard let archive = try self.vault.load(id).epubArchive else { throw VaultFailure.badData }
                    try archive.write(to: url, options: .atomic)
                } catch { self.sendError(error.localizedDescription, context: "book") }
            }
        } catch { sendError(error.localizedDescription, context: "book") }
    }

    @objc private func archiveOtherSecureBooks() {
        guard currentTab == "secure", vault.isUnlocked, let id = currentBookID else { return }
        do {
            let books = try vault.list()
            guard let kept = books.first(where: { $0.id == id }) else { return }
            let timestamp = DateFormatter()
            timestamp.dateFormat = "yyyyMMdd-HHmmss"
            let backups = primaryVault.root.deletingLastPathComponent()
                .appendingPathComponent("FishTouchingReaderBackups", isDirectory: true)
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let destination = backups.appendingPathComponent("secure-backup-\(timestamp.string(from: Date()))-\(UUID().uuidString.prefix(8))")
            let title = kept.encodedTitle.removingPercentEncoding ?? kept.encodedTitle
            let alert = NSAlert()
            alert.messageText = "备份并整理加密书库？"
            alert.informativeText = "保留《\(title)》，将其他 \(books.count - 1) 本从当前书库移除。所有书籍和进度会先加密备份，当前这本的应用内进度随后归零。"
            alert.addButton(withTitle: "备份并整理")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let removed = try vault.archiveOtherBooks(keeping: id, at: destination, resetKeptProgress: true)
            showBook(id)
            let done = NSAlert()
            done.messageText = "已备份，移除 \(removed) 本，当前进度归零"
            done.informativeText = "备份位置：\(destination.path)"
            done.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "备份或整理失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func sendLibrary() {
        guard currentTab == "secure", vault.isUnlocked else { showLocked(); return }
        do {
            let books = try vault.list().map { item -> [String: Any] in
                let pdfProgress = item.kind == "pdf" ? try vault.loadPDFProgress(item.id) : nil
                return ["id": item.id, "title": item.encodedTitle, "host": item.host,
                 "count": item.paragraphCount, "wordCount": item.wordCount,
                 "kind": item.kind, "pageCount": item.pageCount,
                 "paragraph": item.kind == "pdf" ? (pdfProgress?.pageIndex ?? 0) : (item.progress?.paragraph ?? 0),
                 "fraction": item.kind == "pdf" ? (pdfProgress?.fraction ?? 0) : (item.progress?.fraction ?? 0),
                 "updatedAt": item.kind == "pdf" ? (pdfProgress?.updatedAt?.timeIntervalSince1970 ?? 0) : (item.progress?.updatedAt.timeIntervalSince1970 ?? 0),
                 "recentHidden": item.kind == "pdf" ? (pdfProgress?.recentHidden ?? false) : (item.progress?.recentHidden ?? false)]
            }
            send(["type": "library", "books": books,
                  "hotKeyAvailable": hotKeyRegistrationStatus == noErr])
        } catch { sendError(error.localizedDescription, context: "library") }
    }

    private func removeBook(_ id: String, kind: String) {
        do {
            if currentTab == "secure" {
                guard vault.isUnlocked else { return }
                try vault.removeFromLibrary(id)
                if secureResumeID == id { secureResumeID = nil }
                if currentBookID == id { currentBookID = nil }
                sendLibrary()
            } else {
                if kind == "pdf" { try pdfLibrary.removeFromLibrary(id) }
                else if kind == "text" { try textLibrary.removeFromLibrary(id) }
                else { return }
                if currentBookID == id { currentBookID = nil }
                showNormalLibrary()
            }
        } catch { sendError(error.localizedDescription, context: currentTab == "secure" ? "library" : "normal") }
    }

    private func removeRecent(_ id: String, kind: String) {
        do {
            if currentTab == "secure" {
                guard vault.isUnlocked else { return }
                try vault.hideFromRecent(id)
                sendLibrary()
            } else {
                if kind == "pdf" { try pdfLibrary.hideFromRecent(id) }
                else if kind == "text" { try textLibrary.hideFromRecent(id) }
                else { return }
                showNormalLibrary()
            }
        } catch { sendError(error.localizedDescription, context: currentTab == "secure" ? "library" : "normal") }
    }

    private func showNormalLibrary(completion: (() -> Void)? = nil) {
        currentTab = "normal"
        do {
            var pdfs = try pdfLibrary.listWithProgress().map { item -> [String: Any] in
                ["id": item.pdf.id, "title": item.pdf.title,
                 "kind": "pdf",
                 "pageCount": item.pageCount,
                 "pageIndex": item.progress?.pageIndex ?? 0,
                 "pageFraction": item.progress?.fraction ?? 0,
                 "updatedAt": item.progress?.updatedAt?.timeIntervalSince1970 ?? 0,
                 "recentHidden": item.progress?.recentHidden ?? false]
            }
            for item in try textLibrary.list() {
                let progress = try textLibrary.progress(item.id)
                pdfs.append(["id": item.id, "title": item.title, "kind": "text",
                             "pageCount": item.paragraphCount, "pageIndex": progress?.paragraph ?? 0,
                             "pageFraction": progress?.fraction ?? 0,
                             "updatedAt": progress?.updatedAt.timeIntervalSince1970 ?? 0,
                             "recentHidden": progress?.recentHidden ?? false])
            }
            send(["type": "normal", "pdfs": pdfs], completion: completion)
        } catch {
            send(["type": "error", "message": error.localizedDescription, "context": "normal"],
                 completion: completion)
        }
    }

    private func selectNormal() {
        if currentTab == "secure" && vault.isUnlocked {
            secureLock(showNormal: true)
        } else {
            currentTab = "normal"
            showNormalLibrary()
        }
    }

    private func selectSecure() {
        currentBookID = nil
        currentTab = "secure"
        if vault.isUnlocked { sendLibrary() } else { showLocked() }
    }

    private func showLocked(_ error: String? = nil) {
        var payload: [String: Any] = ["type": "locked"]
        if let error { payload["error"] = error }
        send(payload)
    }

    private func unlockSecure(_ password: String) {
        guard currentTab == "secure", !secureTransitioning else { return }
        do {
            vaults.forEach { $0.lock() }
            guard let index = vaults.firstIndex(where: { $0.matchesPassword(password) }) else { throw VaultFailure.wrongPassword }
            try vaults[index].unlock(password: password)
            activeVaultIndex = index
            if let id = secureResumeID, secureResumeVaultIndex == activeVaultIndex,
               try vault.list().contains(where: { $0.id == id }) { showBook(id) }
            else { secureResumeID = nil; sendLibrary() }
        } catch { vaults.forEach { $0.lock() }; showLocked(error.localizedDescription) }
    }

    private func transferBook(_ id: String, password: String) {
        guard currentTab == "secure", vault.isUnlocked else { return }
        guard let targetIndex = vaults.indices.first(where: { $0 != activeVaultIndex && vaults[$0].matchesPassword(password) }) else {
            sendError("另一书库密码不正确，或书库尚未创建。", context: "library"); return
        }
        let target = vaults[targetIndex]
        do {
            try target.unlock(password: password)
            defer { target.lock() }
            _ = try vault.transferBook(id, to: target)
            if secureResumeID == id { secureResumeID = nil }
            if currentBookID == id { currentBookID = nil }
            sendLibrary()
        } catch { sendError(error.localizedDescription, context: "library") }
    }

    private func finishSetup(_ data: [String: Any]) {
        let password = data["password"] as? String ?? ""
        let repeated = data["confirm"] as? String ?? ""
        guard password == repeated else { send(["type": "setup", "error": "两次输入的密码不一致。"]); return }
        do {
            try vault.configure(password: password)
            let name = (data["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            do { try applyName(name) }
            catch { NSLog("App name update failed: %@", error.localizedDescription) }
            showNormalLibrary()
        } catch { send(["type": "setup", "error": error.localizedDescription]) }
    }

    private func chooseIcon(fromSettings: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  let icon = NSImage(contentsOf: url), let tiff = icon.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
            do {
                try FileManager.default.createDirectory(at: self.primaryVault.root, withIntermediateDirectories: true)
                try png.write(to: self.customIconURL, options: .atomic)
                UserDefaults.standard.set("custom", forKey: "appearanceIconID")
                NSApp.applicationIconImage = NSImage(contentsOf: self.customIconURL) ?? icon
                if fromSettings {
                    let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
                    let note = min(width, height) < 1024 ? "图标已更新。图片为 \(width)×\(height)，建议使用至少 1024×1024 的正方形原图。" : "Dock 图标已更新。"
                    self.sendSettingsState(message: note)
                } else {
                    self.webView.evaluateJavaScript("selectSetupIcon('custom')", completionHandler: nil)
                }
            } catch { self.sendError(error.localizedDescription, context: self.currentTab == "secure" ? "library" : "normal") }
        }
    }

    private func choosePresetIcon(_ id: String) {
        guard presetIconIDs.contains(id), let url = iconURL(for: id), let icon = NSImage(contentsOf: url) else {
            sendSettingsState(error: "内置图标无法读取。")
            return
        }
        UserDefaults.standard.set(id, forKey: "appearanceIconID")
        NSApp.applicationIconImage = icon
        sendSettingsState(message: "Dock 图标已更新。")
        webView.evaluateJavaScript("selectSetupIcon('\(id)')", completionHandler: nil)
    }

    private func applyName(_ name: String) throws {
        let input = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = String((input.isEmpty ? AppDefaults.displayName : input).prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
        let original = Bundle.main.bundleURL
        let renamed = original.deletingLastPathComponent().appendingPathComponent(cleaned).appendingPathExtension("app")
        let changesBundlePath = renamed.path.precomposedStringWithCanonicalMapping != original.path.precomposedStringWithCanonicalMapping
        if changesBundlePath && FileManager.default.fileExists(atPath: renamed.path) {
            throw NSError(domain: "Settings", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "同目录已有这个名称的应用，请先处理重名应用。"])
        }
        UserDefaults.standard.set(cleaned, forKey: "pendingDisplayName")
    }

    private func showSettings() {
        guard !settingsVisible, !settingsOpening, !secureTransitioning else { return }
        settingsOpening = true
        settingsVaultIndex = currentTab == "secure" && vault.isUnlocked ? activeVaultIndex : nil
        let present: () -> Void = { [weak self] in
            guard let self else { return }
            self.savePDFProgress(); self.stopObservingPDF()
            self.pdfContainer.isHidden = true; self.pdfView.document = nil
            self.currentPDFID = nil; self.currentPDFIsSecure = false
            self.webView.isHidden = false
            self.settingsVisible = true
            self.settingsOpening = false
            self.webView.evaluateJavaScript("showInlineSettings()") { _, _ in self.sendSettingsState() }
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        if currentTab == "secure", vault.isUnlocked { secureLock(showNormal: true, completion: present) }
        else {
            webView.evaluateJavaScript("window.flushProgress?.()") { _, _ in self.showNormalLibrary(completion: present) }
        }
    }

    private func closeSettings() {
        settingsVisible = false
        webView.evaluateJavaScript("hideInlineSettings()", completionHandler: nil)
        settingsVaultIndex = nil
    }

    private func settingsIconDataURL() -> String {
        guard let tiff = NSApp.applicationIconImage?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return "" }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    private func customIconDataURL() -> String? {
        guard let data = try? Data(contentsOf: customIconURL) else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
    }

    private func sendSettingsState(message: String? = nil, error: String? = nil, restartPrompt: Bool = false) {
        var payload: [String: Any] = ["name": UserDefaults.standard.string(forKey: "pendingDisplayName") ?? displayName,
                                      "icon": settingsIconDataURL(),
                                      "iconID": activeIconID,
                                      "hasCustomIcon": FileManager.default.fileExists(atPath: customIconURL.path),
                                      "passwordScope": settingsVaultIndex.map { "encrypted:\($0)" } ?? "public",
                                      "canChangePassword": settingsVaultIndex != nil,
                                      "canCreatePrivate": vaults.contains { !$0.isConfigured }]
        if let customIcon = customIconDataURL() { payload["customIcon"] = customIcon }
        if let message { payload["message"] = message }
        if let error { payload["error"] = error }
        if restartPrompt { payload["restartPrompt"] = true }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        webView.evaluateJavaScript("receiveSettings(\(json))", completionHandler: nil)
    }

    private func handleSettingsAction(_ action: String, data: [String: Any]) {
        switch action {
        case "ready": sendSettingsState()
        case "closeSettings": closeSettings()
        case "chooseIcon": chooseIcon(fromSettings: true)
        case "selectIcon": choosePresetIcon(data["id"] as? String ?? "")
        case "selectCustomIcon":
            if let icon = NSImage(contentsOf: customIconURL) {
                UserDefaults.standard.set("custom", forKey: "appearanceIconID")
                NSApp.applicationIconImage = icon
                sendSettingsState(message: "Dock 图标已更新。")
            }
        case "deleteCustomIcon":
            let wasSelected = activeIconID == "custom"
            do {
                try FileManager.default.removeItem(at: customIconURL)
                if wasSelected {
                    UserDefaults.standard.set(AppDefaults.iconID, forKey: "appearanceIconID")
                    if let url = iconURL(for: AppDefaults.iconID), let icon = NSImage(contentsOf: url) {
                        NSApp.applicationIconImage = icon
                    }
                }
                sendSettingsState(message: "自定义图标已删除。")
            } catch {
                sendSettingsState(error: "删除自定义图标失败：\(error.localizedDescription)")
            }
        case "saveName":
            let name = (data["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                try applyName(name)
                sendSettingsState(restartPrompt: true)
            } catch { sendSettingsState(error: error.localizedDescription) }
        case "restart": restartForNameChange()
        case "changePassword":
            guard settingsVisible, let settingsVaultIndex else {
                sendSettingsState(error: "请先打开要修改密码的加密书库，再进入设置。"); return
            }
            let old = data["old"] as? String ?? ""
            let new = data["new"] as? String ?? ""
            let confirm = data["confirm"] as? String ?? ""
            guard new == confirm else { sendSettingsState(error: "两次输入的新密码不一致。"); return }
            let target = vaults[settingsVaultIndex]
            guard !vaults.enumerated().contains(where: { $0.offset != settingsVaultIndex && $0.element.matchesPassword(new) })
            else { sendSettingsState(error: "不同书库不能使用相同密码。"); return }
            let wasLocked = !target.isUnlocked
            do {
                try target.changePassword(old: old, new: new)
                if wasLocked { target.lock() }
                sendSettingsState(message: "密码已更新。")
            } catch { sendSettingsState(error: error.localizedDescription) }
        case "createPrivate":
            guard settingsVisible, let slot = vaults.indices.first(where: { !vaults[$0].isConfigured })
            else { sendSettingsState(error: "书库已达到数量上限。"); return }
            let password = data["password"] as? String ?? ""
            let confirm = data["confirm"] as? String ?? ""
            guard password == confirm else { sendSettingsState(error: "两次输入的新密码不一致。"); return }
            guard !vaults.contains(where: { $0.matchesPassword(password) }) else {
                sendSettingsState(error: "不同书库不能使用相同密码。"); return
            }
            do {
                try vaults[slot].configure(password: password)
                vaults[slot].lock()
                sendSettingsState(message: "加密书库已创建。锁定后输入新密码即可进入。")
            } catch { sendSettingsState(error: error.localizedDescription) }
        default: break
        }
    }

    private func restartForNameChange() {
        guard let pending = UserDefaults.standard.string(forKey: "pendingDisplayName") else { return }
        do { try scheduleNameUpdate(pending, reopen: true) }
        catch { sendSettingsState(error: "无法自动重启：\(error.localizedDescription)"); return }
        nameRestartScheduled = true
        savePDFProgress()
        webView.evaluateJavaScript("currentProgress()") { [weak self] value, _ in
            guard let self else { NSApp.terminate(nil); return }
            if let id = self.currentBookID, let position = value as? [String: Any],
               let paragraph = position["paragraph"] as? Int,
               let fraction = position["fraction"] as? Double {
                let progress = ReadingProgress(paragraph: paragraph, fraction: fraction, updatedAt: Date())
                if self.currentTab == "secure", self.vault.isUnlocked { try? self.vault.saveProgress(progress, for: id) }
                else if self.currentTab == "normal" { try? self.textLibrary.saveProgress(progress, for: id) }
            }
            NSApp.terminate(nil)
        }
    }

    private func scheduleNameUpdate(_ name: String, reopen: Bool) throws {
        guard let script = Bundle.main.url(forResource: "rename-helper", withExtension: "sh") else {
            throw NSError(domain: "Settings", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "找不到应用名称更新组件。"])
        }
        UserDefaults.standard.synchronize()
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/zsh")
        helper.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                            Bundle.main.bundleURL.path, name, reopen ? "1" : "0"]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }

    private func handleReadingAppearance(_ action: String, data: [String: Any], source: WKWebView?) -> Bool {
        guard ["readingPreferences", "saveReadingPreferences", "listSystemFonts"].contains(action) else { return false }
        func deliver(_ function: String, _ payload: [String: Any], to view: WKWebView?) {
            guard let bytes = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: bytes, encoding: .utf8) else { return }
            view?.evaluateJavaScript("window.\(function)?.(\(json))", completionHandler: nil)
        }
        if action == "listSystemFonts" {
            let fonts = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()
            deliver("receiveSystemFonts", ["fonts": fonts], to: source)
            return true
        }
        let defaults = UserDefaults.standard
        if action == "readingPreferences", defaults.object(forKey: "readerFontSize") == nil,
           let legacy = data["legacyFontSize"] as? Int, (15...30).contains(legacy) { defaults.set(legacy, forKey: "readerFontSize") }
        if action == "saveReadingPreferences" {
            if let size = data["fontSize"] as? Int, (15...30).contains(size) { defaults.set(size, forKey: "readerFontSize") }
            if let theme = data["theme"] as? String, ["forest", "paper", "light", "midnight", "graphite"].contains(theme) {
                defaults.set(theme, forKey: "readerTheme")
            }
            if let font = data["font"] as? String, font.isEmpty || NSFontManager.shared.availableFontFamilies.contains(font) {
                defaults.set(font, forKey: "readerFont")
            }
        }
        let payload: [String: Any] = ["theme": defaults.string(forKey: "readerTheme") ?? "forest", "font": defaults.string(forKey: "readerFont") ?? "", "fontSize": defaults.object(forKey: "readerFontSize") as? Int ?? 19]
        if action == "saveReadingPreferences" {
            deliver("receiveReadingPreferences", payload, to: webView)
        } else { deliver("receiveReadingPreferences", payload, to: source) }
        return true
    }

    private func sendError(_ message: String, context: String) {
        send(["type": "error", "message": message, "context": context])
    }

    private func send(_ payload: [String: Any], completion: (() -> Void)? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { completion?(); return }
        webView.evaluateJavaScript("receive(\(json))") { _, _ in completion?() }
    }

    @objc private func onLostFocus() {
        cancelWebImport()
        sendWeb(["error":"任务因窗口失焦已取消，请重新预览。", "reset":true])
        webView.evaluateJavaScript("resetSettingsForms()", completionHandler: nil)
        if settingsVisible && settingsVaultIndex != nil { closeSettings() }
        guard window.isVisible, currentTab == "secure", !secureTransitioning else { return }
        if !vault.isUnlocked {
            currentBookID = nil
            showNormalLibrary()
            return
        }
        secureLock(showNormal: true, openCoverPDF: currentBookID != nil)
    }

    @objc private func onOtherAppActivated(_ note: Notification) {
        guard let other = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              other.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        onLostFocus()
    }

    private func secureLock(showNormal: Bool = false, openCoverPDF: Bool = false, completion: (() -> Void)? = nil) {
        guard currentTab == "secure", vault.isUnlocked, !secureTransitioning else { return }
        webView.evaluateJavaScript("resetSettingsForms()", completionHandler: nil)
        if settingsVisible && settingsVaultIndex != nil { closeSettings() }
        secureTransitioning = true
        secureResumeID = currentBookID
        secureResumeVaultIndex = activeVaultIndex
        if currentPDFIsSecure {
            savePDFProgress()
            stopObservingPDF()
            pdfContainer.isHidden = true
            pdfView.document = nil
            currentPDFID = nil
            currentPDFIsSecure = false
        }
        webView.isHidden = true
        var finished = false
        let finish: (Any?) -> Void = { [weak self] value in
            guard let self else { return }
            guard !finished else { return }
            finished = true
            if let id = self.currentBookID,
               let position = value as? [String: Any],
               let paragraph = position["paragraph"] as? Int,
               let fraction = position["fraction"] as? Double {
                try? self.vault.saveProgress(ReadingProgress(paragraph: paragraph,
                                                               fraction: fraction,
                                                               updatedAt: Date()), for: id)
            }
            self.vault.lock()
            if showNormal {
                if !openCoverPDF { self.currentBookID = nil }
                self.currentTab = "normal"
                self.webView.alphaValue = 0
                self.webView.isHidden = false
                self.showNormalLibrary {
                    self.webView.alphaValue = 1
                    if openCoverPDF, let firstPDF = try? self.pdfLibrary.list().first {
                        self.openPDF(firstPDF.id, asCover: true)
                    }
                    self.secureTransitioning = false
                    completion?()
                }
            } else {
                self.showLocked()
                self.webView.isHidden = false
                self.secureTransitioning = false
                completion?()
            }
        }
        webView.evaluateJavaScript("prepareSecureLock()") { value, _ in finish(value) }
        // WebKit may defer JavaScript while the app is inactive. Never leave the secure tab pending.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { finish(nil) }
    }

    private func hideWindow() {
        guard window != nil, window.isVisible else { return }
        savePDFProgress()
        onLostFocus()
        window.orderOut(nil)
    }

    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if currentTab == "secure", !vault.isUnlocked { showLocked() }
    }

    private func toggleWindow() { window.isVisible ? hideWindow() : showWindow() }

    private func handleHotKey() {
        let now = Date()
        guard now.timeIntervalSince(lastHotKeyAt) > 0.45 else { return }
        lastHotKeyAt = now
        toggleWindow()
    }

    private func buildPDFView(in content: NSView) {
        let panel = NSView(frame: content.bounds)
        panel.autoresizingMask = [.width, .height]
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(red: 0.06, green: 0.09, blue: 0.08, alpha: 1).cgColor
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        let back = PointingHandButton(image: NSImage(systemSymbolName: "arrow.left", accessibilityDescription: "返回我的书库") ?? NSImage(),
                            target: self, action: #selector(backFromPDF))
        pdfBackButton = back
        back.translatesAutoresizingMaskIntoConstraints = false
        back.isBordered = false
        back.toolTip = "返回我的书库"
        back.setAccessibilityLabel("返回我的书库")
        bar.addSubview(back)
        let secureButton = PointingHandButton(image: NSImage(systemSymbolName: "lock", accessibilityDescription: "加密书库") ?? NSImage(),
                                    target: self, action: #selector(openSecureFromPDF))
        secureButton.translatesAutoresizingMaskIntoConstraints = false
        secureButton.isBordered = false
        secureButton.toolTip = "加密书库"
        bar.addSubview(secureButton)
        let settingsButton = PointingHandButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置") ?? NSImage(),
                                      target: self, action: #selector(menuSettings))
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.isBordered = false
        settingsButton.toolTip = "设置 (⌘,)"
        bar.addSubview(settingsButton)
        let viewer = PDFView()
        viewer.translatesAutoresizingMaskIntoConstraints = false
        viewer.autoScales = true
        viewer.backgroundColor = NSColor(red: 0.06, green: 0.09, blue: 0.08, alpha: 1)
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        footer.translatesAutoresizingMaskIntoConstraints = false
        pdfOutlineButton = NSPopUpButton(frame: .zero, pullsDown: false)
        pdfOutlineButton.target = self
        pdfOutlineButton.action = #selector(jumpPDFChapter)
        pdfOutlineButton.setAccessibilityLabel("章节目录")
        pdfPreviousButton = NSButton(title: "上一页", target: self, action: #selector(previousPDFPage))
        pdfNextButton = NSButton(title: "下一页", target: self, action: #selector(nextPDFPage))
        pdfPageField = NSTextField(string: "1")
        pdfPageField.alignment = .center
        pdfPageField.target = self
        pdfPageField.action = #selector(jumpPDFPage)
        pdfPageField.setAccessibilityLabel("跳转页码，输入后按回车")
        pdfPageLabel = NSTextField(labelWithString: "/ 1 页")
        pdfPercentLabel = NSTextField(labelWithString: "0.0%")
        pdfReturnButton = NSButton(title: "返回跳转前", target: self, action: #selector(returnPDFJump))
        pdfReturnButton.isHidden = true
        for control in [pdfOutlineButton!, pdfPreviousButton!, pdfPageField!, pdfPageLabel!, pdfNextButton!, pdfPercentLabel!, pdfReturnButton!] as [NSView] { footer.addArrangedSubview(control) }
        pdfOutlineButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
        pdfPageField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        panel.addSubview(bar)
        panel.addSubview(viewer)
        panel.addSubview(footer)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            bar.topAnchor.constraint(equalTo: panel.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            back.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 32),
            back.heightAnchor.constraint(equalToConstant: 32),
            settingsButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -18),
            settingsButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 30),
            settingsButton.heightAnchor.constraint(equalToConstant: 30),
            secureButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -12),
            secureButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            secureButton.widthAnchor.constraint(equalToConstant: 30),
            secureButton.heightAnchor.constraint(equalToConstant: 30),
            viewer.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            viewer.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            viewer.topAnchor.constraint(equalTo: bar.bottomAnchor),
            viewer.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 54)
        ])
        panel.isHidden = true
        content.addSubview(panel)
        pdfContainer = panel
        pdfView = viewer
    }

    private func sendImportPlugins(error: String? = nil, message: String? = nil) {
        var payload: [String: Any] = [:]
        do { payload["plugins"] = try importPlugins.views() }
        catch { payload["error"] = "无法读取插件配置：" + error.localizedDescription }
        if let error { payload["error"] = error }
        if let message { payload["message"] = message }
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("receiveImportPlugins(\(json))", completionHandler: nil)
    }

    private func installImportPlugin() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .zip]
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 262_144 else {
                    throw ImportPluginError(message: "插件包不能超过 256 KB。")
                }
                let plugin = try WebPluginRuntime.manifest(Data(contentsOf: url))
                self.confirmPlugin(plugin, source: url.lastPathComponent)
            } catch { self.sendImportPlugins(error: error.localizedDescription) }
        }
    }

    private func removeImportPlugin(_ id: String) {
        let alert = NSAlert()
        alert.messageText = "移除这个社区插件？"
        alert.informativeText = "已导入的书籍和阅读进度会保留。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do { try self.importPlugins.remove(id); self.sendImportPlugins(message: "插件已移除，书籍保持不变。") }
            catch { self.sendImportPlugins(error: error.localizedDescription) }
        }
    }

    private func cancelWebImport() { webJob?.cancel(); webJob=nil; webPreview=nil }
    private func sendWeb(_ payload:[String:Any]) {
        guard let data=try? JSONSerialization.data(withJSONObject:payload), let json=String(data:data,encoding:.utf8) else{return}
        webView.evaluateJavaScript("receiveWebImport(\(json))",completionHandler:nil)
    }
    private func confirmPlugin(_ plugin:ImportPluginDefinition, source:String) {
        let alert=NSAlert(); alert.messageText="安装社区插件“\(plugin.name)”？"
        let domains = (try? WebPluginRuntime.call("hosts", [plugin.adapter ?? ""])) as? String ?? ""
        let permission=plugin.parser == "website" ? "仅访问 \(domains)；番茄另需访问 lf6-awef.bytetos.com 校验公开字体。Fake-IP 时使用 Cloudflare 加密 DNS，仅发送域名。不运行网页脚本。" : "仅读取你选择的本地文本文件。"
        alert.informativeText="来源：\(source)\n作者：\(plugin.author)（未经认证）\n版本：\(plugin.version)\n权限：\(permission)\n同标识插件将被更新；安装后默认停用。"
        alert.addButton(withTitle:"安装");alert.addButton(withTitle:"取消")
        alert.beginSheetModal(for:window) { [weak self] response in
            guard let self,response == .alertFirstButtonReturn else{return}
            do {try self.importPlugins.install(plugin);self.sendImportPlugins(message:"社区插件已安装，请启用后使用。")}
            catch {self.sendImportPlugins(error:error.localizedDescription)}
        }
    }
    private func installWebPlugin(_ data:[String:Any]) {
        do {
            if let id=data["recommended"] as? String {
                guard let p=try WebPluginRuntime.recommended().first(where:{$0.id==id}) else{return}
                confirmPlugin(p,source:"应用随附的实验性社区规则（非网站官方）");return
            }
            let raw=data["url"] as? String ?? "", job=WebDownloadJob()
            cancelWebImport();webJob=job
            DispatchQueue.global(qos:.userInitiated).async { [weak self] in
                do {let p=try WebPluginRuntime.manifest(job.fetch(raw,limit:262144));DispatchQueue.main.async {guard let self,self.webJob === job else{return};self.webJob=nil;self.confirmPlugin(p,source:raw)}}
                catch {let message=error.localizedDescription;DispatchQueue.main.async {guard let self,self.webJob === job else{return};self.webJob=nil;self.sendImportPlugins(error:message)}}
            }
        } catch {sendImportPlugins(error:error.localizedDescription)}
    }
    private func previewWebsite(_ data:[String:Any]) {
        cancelWebImport()
        guard currentTab == "normal" || vault.isUnlocked else{return}
        do {
            let p=try importPlugins.website(data["id"] as? String ?? ""), raw=data["url"] as? String ?? ""
            _ = try WebPluginRuntime.call("checkURL",[p.adapter!,raw,"book"])
            let job=WebDownloadJob(); webJob=job
            DispatchQueue.global(qos:.userInitiated).async { [weak self] in
                do {
                    let bytes=try job.fetch(raw), html=String(decoding:bytes,as:UTF8.self)
                    let catalogURL = try WebPluginRuntime.call("catalogRequest", [p.adapter!, raw]) as? String ?? ""
                    let catalogJSON = catalogURL.isEmpty ? "" : String(decoding:try job.fetch(catalogURL),as:UTF8.self)
                    guard var preview=try WebPluginRuntime.call("catalog",[p.adapter!,raw,html,catalogJSON]) as? [String:Any] else{return}
                    preview["pluginID"]=p.id;preview["source"]=raw
                    DispatchQueue.main.async {guard let self,self.webJob === job else{return};self.webJob=nil;self.webPreview=preview;self.sendWeb(["preview":preview])}
                } catch {let message=error.localizedDescription;DispatchQueue.main.async {guard let self,self.webJob === job else{return};self.webJob=nil;self.sendWeb(["error":message])}}
            }
        } catch {sendWeb(["error":error.localizedDescription])}
    }
    private func importWebsite(_ data:[String:Any]) {
        guard webJob == nil, let preview=webPreview, let chapters=preview["chapters"] as? [[String:String]], currentTab == "normal" || vault.isUnlocked else{return}
        do {
            let p=try importPlugins.website(preview["pluginID"] as? String ?? "")
            let start=data["start"] as? Int ?? 0,end=data["end"] as? Int ?? 0
            guard start>=1,end>=start,end<=chapters.count,end-start<100 else{throw ImportPluginError(message:"每次请选择有效的 1–100 章范围。")}
            let chosen=Array(chapters[(start-1)..<end]), secure=currentTab == "secure", slot=activeVaultIndex, job=WebDownloadJob()
            let title="\(preview["title"] as? String ?? "网络书籍")（目录第\(start)–\(end)项）"
            webJob=job;webPreview=nil
            DispatchQueue.global(qos:.userInitiated).async { [weak self] in
                do {
                    var paragraphs=[String](), size=0
                    var fontDigests=[String:String]()
                    for (i,c) in chosen.enumerated() {
                        try job.check();if i>0 {Thread.sleep(forTimeInterval:1)};try job.check()
                        _ = try WebPluginRuntime.call("checkURL",[p.adapter!,c["url"]!,"chapter"])
                        let bytes=try job.fetch(c["url"]!);size+=bytes.count
                        guard size<=16*1024*1024 else{throw ImportPluginError(message:"本次导入超过 16 MB 限制。")}
                        let html=String(decoding:bytes,as:UTF8.self)
                        let fontURL=try WebPluginRuntime.call("fontRequest",[p.adapter!,html]) as? String ?? ""
                        if !fontURL.isEmpty, fontDigests[fontURL] == nil {
                            let font=try job.fetch(fontURL,limit:524288)
                            fontDigests[fontURL]=SHA256.hash(data:font).map{String(format:"%02x",$0)}.joined()
                        }
                        let parts=try WebPluginRuntime.call("chapter",[p.adapter!,html,fontDigests[fontURL] ?? ""]) as? [String] ?? []
                        paragraphs += [c["title"]!] + parts
                        DispatchQueue.main.async {guard let self,self.webJob === job else{return};self.sendWeb(["message":"已验证 \(i+1)/\(chosen.count) 章…"])}
                    }
                    let content=paragraphs
                    DispatchQueue.main.async {
                        guard let self,self.webJob === job else{return};self.webJob=nil
                        do {
                            guard (self.currentTab == "secure")==secure,!secure || (self.activeVaultIndex==slot && self.vault.isUnlocked) else{throw ImportPluginError(message:"目标书库已切换或锁定。")}
                            _ = try self.importPlugins.website(p.id)
                            if secure {_ = try self.vault.saveText(title:title,paragraphs:content,sourceURL:preview["source"] as? String ?? "")}
                            else {try self.textLibrary.importParagraphs(content,title:title)}
                            if secure {self.sendLibrary()} else{self.showNormalLibrary()}
                        } catch {self.sendWeb(["error":error.localizedDescription])}
                    }
                } catch {let message=error.localizedDescription;DispatchQueue.main.async {guard let self,self.webJob === job else{return};self.webJob=nil;self.sendWeb(["error":"未保存本次导入："+message])}}
            }
        } catch {sendWeb(["error":error.localizedDescription])}
    }

    private func importLocal() {
        guard currentTab == "normal" || vault.isUnlocked else { return }
        do {
            let extensions = try importPlugins.enabledExtensions()
            guard !extensions.isEmpty else { throw ImportPluginError(message: "没有已启用的导入插件，请先在“导入插件”中启用。") }
            let secure = currentTab == "secure", targetIndex = activeVaultIndex
            let panel = NSOpenPanel()
            panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
            // Unknown community suffixes may not have a registered UTType; the registry still validates every chosen file.
            panel.allowsOtherFileTypes = extensions.contains { UTType(filenameExtension: $0) == nil }
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .OK, !panel.urls.isEmpty else { return }
                var imported = 0
                do {
                    guard (self.currentTab == "secure") == secure, !secure || (self.activeVaultIndex == targetIndex && self.vault.isUnlocked) else {
                        throw ImportPluginError(message: "目标书库已切换或锁定，请重新导入。")
                    }
                    for url in panel.urls {
                        let content = try self.importPlugins.parse(url)
                        if let data = content.pdfData {
                            if secure { _ = try self.vault.savePDF(data: data, title: content.title, pageCount: content.pageCount) }
                            else { _ = try self.pdfLibrary.importData(data, title: content.title, pageCount: content.pageCount) }
                        } else if secure {
                            _ = try self.vault.saveText(title: content.title, paragraphs: content.paragraphs, sourceURL: "", epubArchive: content.epubArchive)
                        } else {
                            try self.textLibrary.importParagraphs(content.paragraphs, title: content.title)
                        }
                        imported += 1
                    }
                    if secure { self.sendLibrary() } else { self.showNormalLibrary() }
                } catch {
                    if secure { self.sendLibrary() } else { self.showNormalLibrary() }
                    self.sendError("已导入 \(imported) 个文件。" + error.localizedDescription, context: secure ? "library" : "normal")
                }
            }
        } catch { sendError(error.localizedDescription, context: currentTab == "secure" ? "library" : "normal") }
    }
    private func importNormalText(_ url: URL) throws {
        try textLibrary.importFile(url)
        showNormalLibrary()
    }
    private func showNormalText(_ id: String) {
        guard currentTab == "normal" else { return }
        do {
            let item = try textLibrary.list().first { $0.id == id }
            guard let item else { throw VaultFailure.badData }
            let paragraphs = try textLibrary.load(id)
            let progress = try textLibrary.progress(id)
            currentBookID = id
            send(["type": "book", "tab": "normal", "id": id, "encodedTitle": item.title,
                  "paragraphs": paragraphs, "paragraph": progress?.paragraph ?? 0,
                  "fraction": progress?.fraction ?? 0])
        } catch { sendError(error.localizedDescription, context: "normal") }
    }

    private func openSecurePDF(_ id: String) {
        guard currentTab == "secure", vault.isUnlocked else { return }
        do {
            let data = try vault.loadPDF(id)
            guard let document = PDFDocument(data: data) else { throw VaultFailure.badData }
            stopObservingPDF()
            pdfView.document = document
            pdfContainer.isHidden = false
            webView.isHidden = true
            if let progress = try vault.loadPDFProgress(id), progress.pageIndex < document.pageCount,
               let page = document.page(at: progress.pageIndex) {
                pdfView.go(to: PDFDestination(page: page, at: NSPoint(x: progress.x, y: progress.y)))
            }
            currentPDFID = id
            currentBookID = id
            secureResumeID = id
            secureResumeVaultIndex = activeVaultIndex
            currentPDFIsSecure = true
            pdfBackButton.toolTip = "返回加密书库"
            pdfBackButton.setAccessibilityLabel("返回加密书库")
            observePDFProgress()
        } catch { sendError(error.localizedDescription, context: "library") }
    }

    private func openPDF(_ id: String, asCover: Bool = false) {
        guard currentTab == "normal" else { return }
        if (try? textLibrary.list().contains(where: { $0.id == id })) == true { showNormalText(id); return }
        do {
            guard try pdfLibrary.list().contains(where: { $0.id == id }),
                  let document = PDFDocument(url: pdfLibrary.fileURL(for: id)) else {
                throw NSError(domain: "PDFLibrary", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "无法打开这个 PDF 文件。"])
            }
            savePDFProgress()
            stopObservingPDF()
            pdfView.document = document
            pdfContainer.isHidden = false
            webView.isHidden = true
            if let progress = try pdfLibrary.loadProgress(for: id),
               progress.pageIndex >= 0, progress.pageIndex < document.pageCount,
               let page = document.page(at: progress.pageIndex),
               progress.x.isFinite, progress.y.isFinite {
                pdfView.go(to: PDFDestination(page: page, at: NSPoint(x: progress.x, y: progress.y)))
            }
            currentPDFID = id
            currentPDFIsCover = asCover
            currentPDFIsSecure = false
            pdfBackButton.toolTip = "返回我的书库"
            pdfBackButton.setAccessibilityLabel("返回我的书库")
            observePDFProgress()
            savePDFProgress()
        } catch { sendError(error.localizedDescription, context: "normal") }
    }

    @objc private func backFromPDF() {
        savePDFProgress()
        stopObservingPDF()
        currentPDFID = nil
        currentPDFIsCover = false
        pdfContainer.isHidden = true
        pdfView.document = nil
        webView.isHidden = false
        if currentPDFIsSecure { currentPDFIsSecure = false; sendLibrary() }
        else { showNormalLibrary() }
    }

    @objc private func openSecureFromPDF() {
        backFromPDF()
        selectSecure()
    }

    private func observePDFProgress() {
        buildPDFOutline()
        updatePDFNavigation()
        NotificationCenter.default.addObserver(self, selector: #selector(pdfPositionChanged),
                                               name: .PDFViewPageChanged, object: pdfView)
        if let scrollView = pdfView.documentView?.enclosingScrollView {
            pdfScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(pdfPositionChanged),
                                                   name: NSView.boundsDidChangeNotification,
                                                   object: scrollView.contentView)
        }
    }

    private func stopObservingPDF() {
        pdfJumpOrigin = nil
        pdfOutlineDestinations.removeAll()
        pdfOutlineButton?.removeAllItems()
        pdfReturnButton?.isHidden = true
        pdfProgressWorkItem?.cancel()
        pdfProgressWorkItem = nil
        NotificationCenter.default.removeObserver(self, name: .PDFViewPageChanged, object: pdfView)
        if let scrollView = pdfScrollView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification,
                                                      object: scrollView.contentView)
            pdfScrollView = nil
        }
    }

    @objc private func pdfPositionChanged() {
        updatePDFNavigation()
        pdfProgressWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.savePDFProgress() }
        pdfProgressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func buildPDFOutline() {
        pdfOutlineDestinations.removeAll()
        pdfOutlineButton.removeAllItems()
        pdfOutlineButton.addItem(withTitle: "章节目录")
        func append(_ outline: PDFOutline, depth: Int) {
            for i in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: i) else { continue }
                if let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination {
                    pdfOutlineDestinations.append(destination)
                    pdfOutlineButton.addItem(withTitle: String(repeating: "　", count: min(depth, 3)) + (child.label ?? "未命名章节"))
                    pdfOutlineButton.lastItem?.tag = pdfOutlineDestinations.count
                }
                append(child, depth: depth + 1)
            }
        }
        if let root = pdfView.document?.outlineRoot { append(root, depth: 0) }
        pdfOutlineButton.isEnabled = !pdfOutlineDestinations.isEmpty
        if pdfOutlineDestinations.isEmpty { pdfOutlineButton.item(at: 0)?.title = "无书签目录" }
    }

    private func updatePDFNavigation() {
        guard let document = pdfView?.document, let page = pdfView.currentPage else { return }
        let index = document.index(for: page)
        guard index != NSNotFound else { return }
        if window.firstResponder !== pdfPageField.currentEditor() { pdfPageField.stringValue = String(index + 1) }
        pdfPageLabel.stringValue = "/ \(document.pageCount) 页"
        pdfPreviousButton.isEnabled = index > 0
        pdfNextButton.isEnabled = index + 1 < document.pageCount
        let bounds = page.bounds(for: pdfView.displayBox)
        let y = pdfView.currentDestination?.point.y ?? bounds.maxY
        let fraction = min(1, max(0, (bounds.maxY - y) / max(1, bounds.height)))
        pdfPercentLabel.stringValue = String(format: "%.1f%%", 100.0 * (Double(index) + Double(fraction)) / Double(max(1, document.pageCount)))
    }

    @objc private func previousPDFPage() { pdfView.goToPreviousPage(nil); updatePDFNavigation() }
    @objc private func nextPDFPage() { pdfView.goToNextPage(nil); updatePDFNavigation() }
    @objc private func jumpPDFPage() {
        guard let document = pdfView.document,
              let number = Int(pdfPageField.stringValue), number >= 1, number <= document.pageCount,
              let page = document.page(at: number - 1) else {
            NSSound.beep(); window.makeFirstResponder(pdfView); updatePDFNavigation(); return
        }
        pdfJumpOrigin = pdfView.currentDestination
        pdfReturnButton.isHidden = false
        window.makeFirstResponder(pdfView)
        pdfView.go(to: page)
        updatePDFNavigation()
    }
    @objc private func jumpPDFChapter() {
        let tag = pdfOutlineButton.selectedItem?.tag ?? 0
        guard tag > 0, tag <= pdfOutlineDestinations.count else { return }
        pdfJumpOrigin = pdfView.currentDestination
        pdfReturnButton.isHidden = false
        pdfView.go(to: pdfOutlineDestinations[tag - 1])
        updatePDFNavigation()
    }
    @objc private func returnPDFJump() {
        if let destination = pdfJumpOrigin { pdfView.go(to: destination) }
        pdfJumpOrigin = nil
        pdfReturnButton.isHidden = true
        updatePDFNavigation()
    }

    private func savePDFProgress() {
        guard !currentPDFIsCover, let id = currentPDFID, let document = pdfView?.document,
              let destination = pdfView.currentDestination,
              let page = destination.page else { return }
        let point = destination.point
        guard point.x.isFinite, point.y.isFinite else { return }
        let bounds = page.bounds(for: pdfView.displayBox)
        let fraction = min(1, max(0, (bounds.maxY - point.y) / max(1, bounds.height)))
        let progress = PDFReadingProgress(pageIndex: document.index(for: page),
                                          x: point.x, y: point.y, fraction: fraction)
        do {
            if currentPDFIsSecure { try vault.savePDFProgress(progress, for: id) }
            else { try pdfLibrary.saveProgress(progress, for: id) }
        }
        catch { NSLog("LocalLibrary PDF progress save failed: %@", error.localizedDescription) }
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.title = displayName
        let appMenu = NSMenu()
        let about = appMenu.addItem(withTitle: "关于 FishTouching Reader…", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "显示书库", action: #selector(menuShow), keyEquivalent: "")
        appMenu.addItem(withTitle: "隐藏书库", action: #selector(menuHide), keyEquivalent: "")
        let settings = appMenu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        settings.keyEquivalentModifierMask = [.command]
        let archive = appMenu.addItem(withTitle: "备份其他加密书籍…", action: #selector(archiveOtherSecureBooks), keyEquivalent: "")
        archive.target = self
        if let updaterController {
            let update = appMenu.addItem(withTitle: "检查更新…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            update.target = updaterController
        }
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "书库") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "书库"
        }
        let menu = NSMenu()
        let toggle = menu.addItem(withTitle: "显示／隐藏　　⌃⌥H", action: #selector(menuToggle), keyEquivalent: "")
        toggle.target = self
        let settings = menu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        settings.keyEquivalentModifierMask = [.command]
        if let updaterController {
            let update = menu.addItem(withTitle: "检查更新…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            update.target = updaterController
        }
        let about = menu.addItem(withTitle: "关于 FishTouching Reader…", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 \(displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        statusItem = item
    }

    @objc private func menuAbout() {
        if aboutWindowController == nil { aboutWindowController = AboutWindowController() }
        aboutWindowController?.present()
    }

    @objc private func menuShow() { showWindow() }
    @objc private func menuHide() { hideWindow() }
    @objc private func menuToggle() { toggleWindow() }
    @objc private func menuSettings() { showSettings() }

    private func installHotKey() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let controller = Unmanaged<AppController>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { controller.handleHotKey() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard status == noErr else { hotKeyRegistrationStatus = status; NSLog("LocalLibrary hotkey handler failed: %d", status); return }
        let identifier = EventHotKeyID(signature: 0x4C4C4942, id: 1)
        hotKeyRegistrationStatus = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey), identifier,
                                                        GetApplicationEventTarget(), 0, &hotKeyRef)
        NSLog("LocalLibrary hotkey registration: %d", hotKeyRegistrationStatus)
    }
}

if CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--probe-keychain") || CommandLine.arguments.contains("--verify-migration") {
    do {
        if CommandLine.arguments.contains("--probe-keychain") { try SelfTest.probeKeychain() }
        else if let index = CommandLine.arguments.firstIndex(of: "--verify-migration"), CommandLine.arguments.indices.contains(index + 1) {
            try SelfTest.verifyMigration(source: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        else { try SelfTest.run() }
        exit(0)
    } catch {
        fputs("Verification failed: \(error)\n", stderr)
        exit(1)
    }
}
let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.run()
