import Foundation

enum EPUBParser {
    static func paragraphs(at url: URL) throws -> [String] {
        guard url.pathExtension.lowercased() == "epub" else { throw VaultFailure.badData }
        let container = try archiveEntry("META-INF/container.xml", in: url)
        try rejectEntities(container)
        let containerXML = try XMLDocument(data: container, options: .nodeLoadExternalEntitiesNever)
        guard let opfPath = try containerXML.nodes(forXPath: "//*[local-name()='rootfile']/@full-path").first?.stringValue,
              !opfPath.isEmpty else { throw VaultFailure.badData }
        let opfData = try archiveEntry(opfPath, in: url)
        try rejectEntities(opfData)
        let opf = try XMLDocument(data: opfData, options: .nodeLoadExternalEntitiesNever)
        let items = try opf.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']").reduce(into: [String: String]()) { result, node in
            guard let element = node as? XMLElement,
                  let id = element.attribute(forName: "id")?.stringValue,
                  let href = element.attribute(forName: "href")?.stringValue else { return }
            result[id] = href
        }
        let base = (opfPath as NSString).deletingLastPathComponent
        var result: [String] = []
        var totalBytes = 0, chapters = 0
        for node in try opf.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']") {
            guard let element = node as? XMLElement,
                  let id = element.attribute(forName: "idref")?.stringValue,
                  let href = items[id],
                  let decoded = href.removingPercentEncoding else { throw VaultFailure.badData }
            let path = NSString.path(withComponents: [base, decoded])
            chapters += 1
            guard chapters <= 10_000 else { throw ImportPluginError(message: "EPUB 章节数量超过安全限制。") }
            let data = try archiveEntry(path, in: url)
            totalBytes += data.count
            guard totalBytes <= 64 * 1024 * 1024 else { throw ImportPluginError(message: "EPUB 解压后正文超过 64 MB。") }
            try rejectEntities(data)
            let document = XMLParser(data: data)
            document.shouldResolveExternalEntities = false
            let collector = TextCollector()
            document.delegate = collector
            guard document.parse() else { throw document.parserError ?? VaultFailure.badData }
            result.append(contentsOf: collector.paragraphs)
        }
        guard !result.isEmpty else { throw VaultFailure.badData }
        return result
    }

    private static func rejectEntities(_ data: Data) throws {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
        guard text.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw ImportPluginError(message: "EPUB 包含不受支持的 XML 实体声明。")
        }
    }

    private static func archiveEntry(_ name: String, in url: URL) throws -> Data {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("-"), name.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[]\\")) == nil, !name.split(separator: "/").contains("..") else { throw VaultFailure.badData }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, name]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
        defer { timeout.cancel(); try? output.fileHandleForReading.close() }
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            guard data.count + chunk.count <= 16 * 1024 * 1024 else {
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                throw ImportPluginError(message: "EPUB 单章解压后超过 16 MB。")
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { throw VaultFailure.badData }
        return data
    }
}

private final class TextCollector: NSObject, XMLParserDelegate {
    private(set) var paragraphs: [String] = []
    private var buffer = ""
    private var ignoredDepth = 0
    private let ignored: Set<String> = ["head", "script", "style", "svg", "nav"]
    private let blocks: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "section", "article", "br"]

    private func flush() {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
        if !value.isEmpty { paragraphs.append(value) }
        buffer = ""
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if ignoredDepth > 0 { ignoredDepth += 1; return }
        if ignored.contains(tag) { flush(); ignoredDepth = 1; return }
        if blocks.contains(tag) { flush() }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if ignoredDepth == 0 { buffer += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if ignoredDepth > 0 { ignoredDepth -= 1; return }
        let tag = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if blocks.contains(tag) { flush() }
    }
}
