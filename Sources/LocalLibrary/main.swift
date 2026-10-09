import AppKit
import WebKit
import Carbon
import Foundation
import PDFKit
import UniformTypeIdentifiers

private final class PointingHandButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private enum AppDefaults {
    static let displayName = "摸鱼阅读"
    static let iconID = "fish"
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private let vault = Vault()
    private let pdfLibrary = PDFLibrary()
    private let textLibrary = TextLibrary()
    private var window: NSWindow!
    private var webView: WKWebView!
    private var settingsWindow: NSWindow?
    private var settingsWebView: WKWebView?
    private var nameRestartScheduled = false
    private var pdfContainer: NSView!
    private var pdfView: PDFView!
    private var pdfBackButton: NSButton!
    private var currentPDFID: String?
    private var currentPDFIsCover = false
    private var currentPDFIsSecure = false
    private var pdfScrollView: NSScrollView?
    private var pdfProgressWorkItem: DispatchWorkItem?
    private var pendingImport: ImportedBook?
    private var currentBookID: String?
    private var secureResumeID: String?
    private var currentTab = "normal"
    private var secureTransitioning = false
    private var batchGeneration = UUID()
    private var batchRunning = false
    private var batchStatus: String?
    private var batchFailures: [String] = []
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeyRegistrationStatus: OSStatus = -1
    private var lastHotKeyAt = Date.distantPast
    private var statusItem: NSStatusItem?
    private let presetIconIDs: Set<String> = ["book", "fish", "night", "leaf", "coffee", "star", "pencil", "music", "sunrise", "cloud"]
    private var displayName: String { UserDefaults.standard.string(forKey: "displayName") ?? AppDefaults.displayName }
    private var customIconURL: URL { vault.root.appendingPathComponent("appearance-icon.png") }
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
        vault.lock()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === settingsWindow { return true }
        hideWindow()
        return false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === settingsWebView { sendSettingsState(); return }
        if vault.needsSetup { send(["type": "setup", "iconID": activeIconID]); return }
        if currentTab == "secure" {
            vault.lock()
            showLocked()
        } else { showNormalLibrary() }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let data = message.body as? [String: Any], let action = data["action"] as? String else { return }
        if message.name == "settings" { handleSettingsAction(action, data: data); return }
        switch action {
        case "retry": currentTab == "secure" ? showLocked() : showNormalLibrary()
        case "selectNormal": selectNormal()
        case "selectSecure": selectSecure()
        case "unlock": unlockSecure(data["password"] as? String ?? "")
        case "setup": finishSetup(data)
        case "settings": showSettings()
        case "chooseIcon": chooseIcon()
        case "selectIcon": choosePresetIcon(data["id"] as? String ?? "")
        case "importLocal": importLocal()
        case "lock": secureLock()
        case "importPDF": importLocal()
        case "openPDF":
            if let id = data["id"] as? String { openPDF(id) }
        case "import": startImport(data["url"] as? String ?? "")
        case "importIndex": startIndexImport(data["url"] as? String ?? "")
        case "saveImport":
            guard currentTab == "secure", vault.isUnlocked, let imported = pendingImport else { return }
            do { _ = try vault.save(imported); pendingImport = nil; sendLibrary() }
            catch { sendError(error.localizedDescription, context: "preview") }
        case "cancelImport": pendingImport = nil; sendLibrary()
        case "library":
            currentBookID = nil
            if currentTab == "secure" { secureResumeID = nil; sendLibrary() }
            else { showNormalLibrary() }
        case "read":
            guard let id = data["id"] as? String else { return }
            if currentTab == "secure" { showBook(id) } else { showNormalText(id) }
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

    private func startImport(_ input: String) {
        guard currentTab == "secure", vault.isUnlocked else { showLocked(); return }
        guard !batchRunning else { return }
        let url: URL
        do { url = try WordPressImporter.validatedURL(input) }
        catch { sendError(error.localizedDescription, context: "library"); return }
        send(["type": "busy", "message": "正在下载和提取正文…"])
        WordPressImporter.fetch(url) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.currentTab == "secure", self.vault.isUnlocked else { return }
                switch result {
                case .success(let imported):
                    self.pendingImport = imported
                    self.send(["type": "preview", "encodedTitle": imported.encodedTitle,
                               "originalTitle": imported.originalTitle,
                               "count": imported.paragraphs.count,
                               "sample": imported.paragraphs.prefix(8).joined(separator: "\n")])
                case .failure(let error): self.sendError(error.localizedDescription, context: "library")
                }
            }
        }
    }

    private func showBook(_ id: String) {
        cancelBatch()
        do {
            if try vault.list().contains(where: { $0.id == id && $0.kind == "pdf" }) {
                openSecurePDF(id); return
            }
            let book = try vault.load(id)
            let progress = try vault.loadProgress(id)
            currentBookID = id
            secureResumeID = id
            send(["type": "book", "id": id, "encodedTitle": book.encodedTitle,
                  "paragraphs": book.paragraphs, "paragraph": progress?.paragraph ?? 0,
                  "fraction": progress?.fraction ?? 0])
        } catch { sendError(error.localizedDescription, context: "library") }
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
                 "updatedAt": item.kind == "pdf" ? (pdfProgress?.updatedAt?.timeIntervalSince1970 ?? 0) : (item.progress?.updatedAt.timeIntervalSince1970 ?? 0)]
            }
            send(["type": "library", "books": books,
                  "batchStatus": batchStatus ?? "",
                  "batchRunning": batchRunning,
                  "batchFailures": batchFailures,
                  "hotKeyAvailable": hotKeyRegistrationStatus == noErr])
        } catch { sendError(error.localizedDescription, context: "library") }
    }

    private func showNormalLibrary() {
        currentTab = "normal"
        do {
            var pdfs = try pdfLibrary.listWithProgress().map { item -> [String: Any] in
                ["id": item.pdf.id, "title": item.pdf.title,
                 "kind": "pdf",
                 "pageCount": item.pageCount,
                 "pageIndex": item.progress?.pageIndex ?? 0,
                 "pageFraction": item.progress?.fraction ?? 0,
                 "updatedAt": item.progress?.updatedAt?.timeIntervalSince1970 ?? 0]
            }
            for item in try textLibrary.list() {
                let progress = try textLibrary.progress(item.id)
                pdfs.append(["id": item.id, "title": item.title, "kind": "text",
                             "pageCount": item.paragraphCount, "pageIndex": progress?.paragraph ?? 0,
                             "pageFraction": progress?.fraction ?? 0,
                             "updatedAt": progress?.updatedAt.timeIntervalSince1970 ?? 0])
            }
            send(["type": "normal", "pdfs": pdfs])
        } catch {
            sendError(error.localizedDescription, context: "normal")
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
        if currentTab == "normal" { currentBookID = secureResumeID }
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
            try vault.unlock(password: password)
            if let id = secureResumeID { showBook(id) } else { sendLibrary() }
        } catch { showLocked(error.localizedDescription) }
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
        panel.beginSheetModal(for: (fromSettings ? settingsWindow : window) ?? window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  let icon = NSImage(contentsOf: url), let tiff = icon.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
            do {
                try FileManager.default.createDirectory(at: self.vault.root, withIntermediateDirectories: true)
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
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            sendSettingsState()
            return
        }
        let configuration = WKWebViewConfiguration()
        let messages = WKUserContentController()
        messages.add(self, name: "settings")
        configuration.userContentController = messages
        let settingsView = WKWebView(frame: .zero, configuration: configuration)
        settingsView.navigationDelegate = self
        settingsView.autoresizingMask = [.width, .height]
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        panel.title = "设置 · \(displayName)"
        panel.minSize = NSSize(width: 660, height: 460)
        panel.center()
        panel.contentView = settingsView
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        settingsWindow = panel
        settingsWebView = settingsView
        let url = Bundle.main.url(forResource: "settings", withExtension: "html")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/settings.html")
        settingsView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        guard let settingsWebView else { return }
        var payload: [String: Any] = ["name": UserDefaults.standard.string(forKey: "pendingDisplayName") ?? displayName,
                                      "icon": settingsIconDataURL(),
                                      "iconID": activeIconID,
                                      "hasCustomIcon": FileManager.default.fileExists(atPath: customIconURL.path)]
        if let customIcon = customIconDataURL() { payload["customIcon"] = customIcon }
        if let message { payload["message"] = message }
        if let error { payload["error"] = error }
        if restartPrompt { payload["restartPrompt"] = true }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        settingsWebView.evaluateJavaScript("receiveSettings(\(json))", completionHandler: nil)
    }

    private func handleSettingsAction(_ action: String, data: [String: Any]) {
        switch action {
        case "ready": sendSettingsState()
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
            let old = data["old"] as? String ?? ""
            let new = data["new"] as? String ?? ""
            let confirm = data["confirm"] as? String ?? ""
            guard new == confirm else { sendSettingsState(error: "两次输入的新密码不一致。"); return }
            let wasLocked = !vault.isUnlocked
            do {
                try vault.changePassword(old: old, new: new)
                if wasLocked { vault.lock() }
                sendSettingsState(message: "密码已更新。")
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

    private func sendError(_ message: String, context: String) {
        send(["type": "error", "message": message, "context": context])
    }

    private func send(_ payload: [String: Any], completion: (() -> Void)? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { completion?(); return }
        webView.evaluateJavaScript("receive(\(json))") { _, _ in completion?() }
    }

    @objc private func onLostFocus() {
        guard window.isVisible, currentTab == "secure", vault.isUnlocked, !secureTransitioning else { return }
        // The PDF panel can cover the web view; only its encrypted document needs the disguise.
        if !pdfContainer.isHidden && !currentPDFIsSecure { return }
        secureLock(showNormal: true, openCoverPDF: true)
    }

    @objc private func onOtherAppActivated(_ note: Notification) {
        guard let other = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              other.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        onLostFocus()
    }

    private func secureLock(showNormal: Bool = false, openCoverPDF: Bool = false) {
        guard currentTab == "secure", vault.isUnlocked, !secureTransitioning else { return }
        cancelBatch()
        secureTransitioning = true
        secureResumeID = currentBookID
        if currentPDFIsSecure {
            savePDFProgress()
            stopObservingPDF()
            pdfContainer.isHidden = true
            pdfView.document = nil
            currentPDFID = nil
            currentPDFIsSecure = false
        }
        webView.isHidden = true
        webView.evaluateJavaScript("prepareSecureLock()") { [weak self] value, _ in
            guard let self else { return }
            if let id = self.currentBookID,
               let position = value as? [String: Any],
               let paragraph = position["paragraph"] as? Int,
               let fraction = position["fraction"] as? Double {
                try? self.vault.saveProgress(ReadingProgress(paragraph: paragraph,
                                                               fraction: fraction,
                                                               updatedAt: Date()), for: id)
            }
            self.vault.lock()
            self.pendingImport = nil
            if showNormal {
                if !openCoverPDF { self.currentBookID = nil }
                self.currentTab = "normal"
                self.showNormalLibrary()
                self.webView.isHidden = false
                if openCoverPDF, let firstPDF = try? self.pdfLibrary.list().first {
                    self.openPDF(firstPDF.id, asCover: true)
                }
                self.secureTransitioning = false
            } else {
                self.showLocked()
                self.webView.isHidden = false
                self.secureTransitioning = false
            }
        }
    }

    private func cancelBatch() {
        batchGeneration = UUID()
        batchRunning = false
        batchStatus = nil
        batchFailures = []
    }

    private func startIndexImport(_ input: String) {
        guard currentTab == "secure", vault.isUnlocked, !batchRunning else { return }
        let url: URL
        do { url = try WordPressImporter.validatedURL(input) }
        catch { sendError(error.localizedDescription, context: "library"); return }
        batchRunning = true
        batchFailures = []
        let generation = UUID()
        batchGeneration = generation
        batchStatus = "正在读取目录…"
        send(["type": "batch", "message": batchStatus!])
        WordPressImporter.fetchIndex(url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.batchGeneration == generation,
                      self.currentTab == "secure", self.vault.isUnlocked else { return }
                do {
                    let links = try result.get()
                    let existing = Set(try self.vault.list().map(\.sourceURL))
                    let remaining = links.filter { !existing.contains($0.absoluteString) }
                    self.importNext(remaining, at: 0, generation: generation,
                                    skipped: links.count - remaining.count, imported: 0, failed: 0)
                } catch {
                    self.batchRunning = false
                    self.batchStatus = nil
                    self.sendLibrary()
                    self.sendError(error.localizedDescription, context: "library")
                }
            }
        }
    }

    private func importNext(_ urls: [URL], at index: Int, generation: UUID,
                            skipped: Int, imported: Int, failed: Int) {
        guard batchGeneration == generation, currentTab == "secure", vault.isUnlocked else { return }
        guard index < urls.count else {
            batchRunning = false
            batchStatus = "目录导入完成：新增 \(imported) 本，跳过已有 \(skipped) 本，失败 \(failed) 本。"
            sendLibrary()
            return
        }
        batchStatus = "逐篇导入中：\(index + 1)/\(urls.count)，已保存 \(imported) 本，失败 \(failed) 本。"
        send(["type": "batch", "message": batchStatus!])
        WordPressImporter.fetch(urls[index]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.batchGeneration == generation,
                      self.currentTab == "secure", self.vault.isUnlocked else { return }
                var newImported = imported
                var newFailed = failed
                do { _ = try self.vault.save(result.get()); newImported += 1 }
                catch {
                    newFailed += 1
                    self.batchFailures.append(urls[index].absoluteString)
                    NSLog("LocalLibrary index import failed: %@ (%@)", urls[index].absoluteString, error.localizedDescription)
                }
                self.importNext(urls, at: index + 1, generation: generation,
                                skipped: skipped, imported: newImported, failed: newFailed)
            }
        }
    }

    private func hideWindow() {
        guard window != nil, window.isVisible else { return }
        savePDFProgress()
        if currentTab == "secure", vault.isUnlocked { secureLock(showNormal: true, openCoverPDF: true) }
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
        panel.addSubview(bar)
        panel.addSubview(viewer)
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
            viewer.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        panel.isHidden = true
        content.addSubview(panel)
        pdfContainer = panel
        pdfView = viewer
    }

    private func importLocal() {
        guard currentTab == "normal" || vault.isUnlocked else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                if self.currentTab == "secure" {
                    let data = try Data(contentsOf: url)
                    if url.pathExtension.lowercased() == "pdf" {
                        guard let pdf = PDFDocument(data: data) else { throw VaultFailure.badData }
                        _ = try self.vault.savePDF(data: data, title: url.deletingPathExtension().lastPathComponent, pageCount: pdf.pageCount)
                    } else {
                        guard let text = PlainTextDecoder.decode(data) else { throw VaultFailure.badData }
                        let paragraphs = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        _ = try self.vault.saveText(title: url.deletingPathExtension().lastPathComponent, paragraphs: paragraphs, sourceURL: "")
                    }
                    self.sendLibrary()
                } else if url.pathExtension.lowercased() == "pdf" {
                    try self.pdfLibrary.importFile(url); self.showNormalLibrary()
                } else {
                    try self.importNormalText(url)
                }
            } catch { self.sendError(error.localizedDescription, context: self.currentTab == "secure" ? "library" : "normal") }
        }
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
        pdfProgressWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.savePDFProgress() }
        pdfProgressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
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
        appMenu.addItem(withTitle: "显示书库", action: #selector(menuShow), keyEquivalent: "")
        appMenu.addItem(withTitle: "隐藏书库", action: #selector(menuHide), keyEquivalent: "")
        let settings = appMenu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        settings.keyEquivalentModifierMask = [.command]
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 \(displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        statusItem = item
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

if CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--verify-live") || CommandLine.arguments.contains("--probe-keychain") || CommandLine.arguments.contains("--verify-migration") {
    do {
        if CommandLine.arguments.contains("--probe-keychain") { try SelfTest.probeKeychain() }
        else if let index = CommandLine.arguments.firstIndex(of: "--verify-migration"), CommandLine.arguments.indices.contains(index + 1) {
            try SelfTest.verifyMigration(source: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        else { try SelfTest.run(live: CommandLine.arguments.contains("--verify-live")) }
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
