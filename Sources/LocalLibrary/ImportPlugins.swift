import Foundation
import PDFKit

struct ImportPluginDefinition: Codable {
    let id: String
    let name: String
    let version: String
    let author: String
    let description: String
    let extensions: [String]
    let parser: String
    let schemaVersion: Int
    var adapter: String? = nil

    var isOfficial: Bool { id.hasPrefix("official.") }
    func view(enabled: Bool) -> [String: Any] {
        ["id": id, "name": name, "version": version, "author": author, "description": description,
         "extensions": extensions, "origin": isOfficial ? "official" : "community", "enabled": enabled,
         "parser": parser, "adapter": adapter ?? "",
         "permissions": parser == "website" ? "仅访问该书源适配器允许的 HTTPS 网站；不执行网页脚本，不访问其他书籍。" : "仅读取你选择的本地文件；不能联网或访问其他书籍"]
    }
}

struct ImportedBookContent {
    let title: String
    let paragraphs: [String]
    let pdfData: Data?
    let pageCount: Int
    let epubArchive: Data?
}

struct ImportPluginError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Only built-in parsers execute code. Community manifests are bounded data, never scripts.
final class ImportPluginRegistry {
    private struct Configuration: Codable {
        var community: [ImportPluginDefinition] = []
        var disabled: [String] = []
    }
    static let official: [ImportPluginDefinition] = [
        .init(id: "official.txt", name: "TXT 文本", version: "1.0.0", author: "YouDiSN", description: "导入纯文本，自动识别常用文字编码。", extensions: ["txt"], parser: "txt", schemaVersion: 1),
        .init(id: "official.pdf", name: "PDF 文档", version: "1.0.0", author: "YouDiSN", description: "保留原始页面、图片与书签。", extensions: ["pdf"], parser: "pdf", schemaVersion: 1),
        .init(id: "official.epub", name: "EPUB 电子书", version: "1.0.0", author: "YouDiSN", description: "按书籍顺序提取文字；加密书库保留原始 EPUB。", extensions: ["epub"], parser: "epub", schemaVersion: 1)
    ]
    private let root: URL
    private var configURL: URL { root.appendingPathComponent("plugins.json") }
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalLibrary/import-plugins", isDirectory: true)
    }
    private func configuration() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return Configuration() }
        guard let size = try configURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 512_000 else {
            throw ImportPluginError(message: "插件配置过大，请检查插件目录。")
        }
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(Configuration.self, from: data)
        guard config.community.count <= 50 else { throw ImportPluginError(message: "最多安装 50 个社区插件。") }
        var ids = Set<String>(), suffixes = Set<String>()
        for plugin in config.community {
            _ = try Self.validate(JSONEncoder().encode(plugin))
            guard ids.insert(plugin.id).inserted, plugin.extensions.allSatisfy({ suffixes.insert($0).inserted }) else {
                throw ImportPluginError(message: "社区插件之间存在重复标识或文件类型。")
            }
        }
        return config
    }
    private func save(_ config: Configuration) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(config).write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }
    static func validate(_ data: Data) throws -> ImportPluginDefinition {
        if data.count <= 65_536, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["schemaVersion"] as? Int == 2 {
            _ = try WebPluginRuntime.call("validate", [object])
            return try JSONDecoder().decode(ImportPluginDefinition.self, from: data)
        }
        guard data.count <= 65_536,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["schemaVersion", "id", "name", "version", "author", "description", "extensions", "parser"]) else {
            throw ImportPluginError(message: "仅支持规范的 JSON 插件规则（最大 64 KB），不接受脚本、网络权限或自定义身份声明。")
        }
        let plugin = try JSONDecoder().decode(ImportPluginDefinition.self, from: data)
        func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
        guard plugin.schemaVersion == 1,
              matches(plugin.id, "^community\\.[a-z0-9][a-z0-9.-]{0,62}$"),
              matches(plugin.version, "^[0-9]{1,4}\\.[0-9]{1,4}\\.[0-9]{1,4}$"),
              !plugin.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, plugin.name.count <= 60,
              !plugin.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, plugin.author.count <= 80,
              plugin.description.count <= 300,
              plugin.parser == "txt", !plugin.extensions.isEmpty, plugin.extensions.count <= 8,
              Set(plugin.extensions).count == plugin.extensions.count,
              plugin.extensions.allSatisfy({ matches($0, "^[a-z][a-z0-9]{0,9}$") && !["txt", "pdf", "epub"].contains($0) }) else {
            throw ImportPluginError(message: "社区插件格式不合法。本版支持本地文本格式扩展，不能覆盖官方 TXT／PDF／EPUB，也不执行网址或脚本。")
        }
        return plugin
    }
    func website(_ id: String) throws -> ImportPluginDefinition {
        let config = try configuration()
        guard let p = config.community.first(where: { $0.id == id && $0.parser == "website" }), !config.disabled.contains(id) else { throw ImportPluginError(message: "请先安装并启用书源插件。") }; return p
    }
    func views() throws -> [[String: Any]] {
        let config = try configuration()
        return (Self.official + config.community).map { $0.view(enabled: !config.disabled.contains($0.id)) }
    }
    func enabledExtensions() throws -> [String] {
        let config = try configuration()
        return (Self.official + config.community).filter { !config.disabled.contains($0.id) }.flatMap(\.extensions)
    }
    func install(_ plugin: ImportPluginDefinition) throws {
        let plugin = try Self.validate(JSONEncoder().encode(plugin))
        var config = try configuration()
        let other = config.community.filter { $0.id != plugin.id }
        guard other.count < 50, !other.contains(where: { !Set($0.extensions).isDisjoint(with: plugin.extensions) }) else {
            throw ImportPluginError(message: "插件数量达到上限，或扩展名已被其他社区插件使用。")
        }
        config.community = other + [plugin]
        // Updates also require explicit enablement after the permissions review.
        if !config.disabled.contains(plugin.id) { config.disabled.append(plugin.id) }
        try save(config)
    }
    func setEnabled(_ id: String, enabled: Bool) throws {
        var config = try configuration()
        guard (Self.official + config.community).contains(where: { $0.id == id }) else { throw ImportPluginError(message: "插件不存在。") }
        config.disabled.removeAll { $0 == id }
        if !enabled { config.disabled.append(id) }
        try save(config)
    }
    func remove(_ id: String) throws {
        var config = try configuration()
        guard config.community.contains(where: { $0.id == id }) else { throw ImportPluginError(message: "官方插件不能卸载，可以停用。") }
        config.community.removeAll { $0.id == id }; config.disabled.removeAll { $0 == id }
        try save(config)
    }
    func parse(_ url: URL) throws -> ImportedBookContent {
        let config = try configuration()
        guard let plugin = (Self.official + config.community).first(where: { $0.extensions.contains(url.pathExtension.lowercased()) && !config.disabled.contains($0.id) }) else {
            throw ImportPluginError(message: "没有已启用的插件支持这个文件，请在“导入插件”中检查。")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 256 * 1024 * 1024 else {
            throw ImportPluginError(message: "文件为空、不是普通文件，或超过 256 MB。")
        }
        let title = url.deletingPathExtension().lastPathComponent
        switch plugin.parser {
        case "pdf":
            let data = try Data(contentsOf: url)
            guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
                throw ImportPluginError(message: "PDF 损坏、没有页面，或需要先解除文件密码保护。")
            }
            return .init(title: title, paragraphs: [], pdfData: data, pageCount: document.pageCount, epubArchive: nil)
        case "epub":
            return try .init(title: title, paragraphs: EPUBParser.paragraphs(at: url), pdfData: nil, pageCount: 0, epubArchive: Data(contentsOf: url))
        default:
            guard size <= 32 * 1024 * 1024 else { throw ImportPluginError(message: "文本文件超过 32 MB，请先拆分。") }
            guard let text = PlainTextDecoder.decode(try Data(contentsOf: url)) else { throw ImportPluginError(message: "无法识别文本编码。") }
            let paragraphs = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !paragraphs.isEmpty else { throw ImportPluginError(message: "文件没有可阅读的正文。") }
            return .init(title: title, paragraphs: paragraphs, pdfData: nil, pageCount: 0, epubArchive: nil)
        }
    }
}
