import Foundation

enum ImportPluginSelfTest {
    static func run(root: URL, text: URL, pdf: URL, epub: URL) throws {
        func check(_ ok: Bool, _ name: String) throws {
            if !ok { throw ImportPluginError(message: "Plugin self-test failed: " + name) }
        }
        let registryRoot = root.appendingPathComponent("plugin-test")
        let registry = ImportPluginRegistry(root: registryRoot)
        try check(try registry.views().count == 3, "three built-in plugins")
        try check(try registry.views().allSatisfy { $0["origin"] as? String == "official" }, "official identity")
        try check(try registry.parse(text).paragraphs.count == 2, "TXT parser")
        try check(try registry.parse(pdf).pageCount == 1, "PDF parser")
        try check(try registry.parse(epub).epubArchive != nil, "EPUB original retained")
        try registry.setEnabled("official.txt", enabled: false)
        try check((try? registry.parse(text)) == nil, "disabled parser rejected")
        try check((try? registry.remove("official.txt")) == nil, "official removal rejected")
        try registry.setEnabled("official.txt", enabled: true)
        let manifest: [String: Any] = ["schemaVersion": 1, "id": "community.fixture", "name": "虚构文本插件", "version": "1.0.0", "author": "测试", "description": "临时目录测试", "extensions": ["md"], "parser": "txt"]
        let plugin = try ImportPluginRegistry.validate(JSONSerialization.data(withJSONObject: manifest))
        try registry.install(plugin)
        let file = root.appendingPathComponent("fixture.md")
        try Data("虚构内容第一行。\n虚构内容第二行。".utf8).write(to: file)
        try check((try? registry.parse(file)) == nil, "community initially disabled")
        try registry.setEnabled(plugin.id, enabled: true)
        let reopened = ImportPluginRegistry(root: registryRoot)
        try check(try reopened.parse(file).paragraphs.count == 2, "community load and persistence")
        try check(try reopened.views().last?["origin"] as? String == "community", "community identity")
        let library = TextLibrary(root: root.appendingPathComponent("plugin-library"))
        let content = try reopened.parse(file)
        try library.importParagraphs(content.paragraphs, title: content.title)
        let id = try library.list()[0].id
        try library.saveProgress(ReadingProgress(paragraph: 1, fraction: 0.4, updatedAt: Date()), for: id)
        try reopened.install(plugin)
        try check((try? reopened.parse(file)) == nil, "update needs enablement")
        try reopened.remove(plugin.id)
        try check(try library.load(id).count == 2 && library.progress(id)?.paragraph == 1, "uninstall retains book and progress")
        try check(FileManager.default.fileExists(atPath: file.path), "original retained")
        for (key, value) in [("id", "official.txt" as Any), ("parser", "javascript" as Any), ("origin", "official" as Any), ("extensions", ["pdf"] as Any), ("permissions", ["network"] as Any)] {
            var invalid = manifest; invalid[key] = value
            let data = try JSONSerialization.data(withJSONObject: invalid)
            try check((try? ImportPluginRegistry.validate(data)) == nil, "rejected " + key)
        }
        try check((try? ImportPluginRegistry.validate(Data(repeating: 32, count: 65537))) == nil, "manifest size cap")
        try check(try registry.views().count == 3, "officials retained after uninstall")
        for p in try WebPluginRuntime.recommended() {
            let encoded = try JSONEncoder().encode(p)
            try check(try WebPluginRuntime.manifest(encoded).id == p.id, "website manifest")
            try registry.install(p)
            try check((try? registry.website(p.id)) == nil, "website starts disabled")
            try registry.setEnabled(p.id, enabled: true)
            try check(try registry.website(p.id).parser == "website", "website enabled")
            try registry.remove(p.id)
        }
        for ip in ["127.0.0.1", "10.0.0.1", "169.254.169.254", "100.64.0.1", "192.168.1.1", "172.16.0.1", "198.18.0.1", "::1"] {
            try check(!WebDownloadJob.publicIPv4(ip), "reject private IP")
        }
        try check(WebDownloadJob.publicIPv4("8.8.8.8"), "public IPv4")
        for url in ["http://example.com/a", "https://user@example.com/a", "https://example.com:443/a", "https://example.com/../a"] {
            try check((try? WebPluginRuntime.call("address", [url])) == nil, "reject unsafe URL")
        }
        let zipDir = root.appendingPathComponent("plugin-package")
        try FileManager.default.createDirectory(at: zipDir, withIntermediateDirectories: true)
        let manifestURL = zipDir.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(WebPluginRuntime.recommended()[0]).write(to: manifestURL)
        let zipURL = root.appendingPathComponent("plugin.zip"), zipper = Process()
        zipper.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipper.arguments = ["-q", "-j", zipURL.path, manifestURL.path]
        try zipper.run(); zipper.waitUntilExit()
        try check(try WebPluginRuntime.manifest(Data(contentsOf: zipURL)).parser == "website", "ZIP install")
        let job = WebDownloadJob(); job.cancel()
        try check((try? job.fetch("https://example.com/plugin.json")) == nil, "cancel before request")
        print("Plugin self-test passed: TXT/PDF/EPUB, provenance, permissions, persistence, progress compatibility")
    }
}
