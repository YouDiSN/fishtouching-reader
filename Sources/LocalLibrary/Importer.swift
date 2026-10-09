import Foundation
import SwiftSoup

struct ImportedBook {
    let sourceURL: String
    let encodedTitle: String
    let originalTitle: String
    let paragraphs: [String]
}

enum ImportFailure: LocalizedError {
    case invalidURL
    case unsupportedSite
    case badResponse
    case missingContent

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入有效的 http 或 https 网址。"
        case .unsupportedSite: return "这个页面无法自动提取正文，请检查页面结构。"
        case .badResponse: return "网页下载失败，请稍后重试。"
        case .missingContent: return "没有找到文章正文；这个页面可能使用了不同的模板。"
        }
    }
}

enum WordPressImporter {
    private static let session = URLSession(configuration: .ephemeral)
    static func fetchHTML(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 35
        request.cachePolicy = .reloadIgnoringLocalCacheData
        session.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  let data,
                  let html = String(data: data, encoding: .utf8) else {
                completion(.failure(ImportFailure.badResponse))
                return
            }
            completion(.success(html))
        }.resume()
    }

    static func fetch(_ url: URL, completion: @escaping (Result<ImportedBook, Error>) -> Void) {
        fetchHTML(url) { result in
            completion(result.flatMap { html in Result { try extract(html: html, sourceURL: url) } })
        }
    }

    static func fetchIndex(_ url: URL, completion: @escaping (Result<[URL], Error>) -> Void) {
        fetchHTML(url) { result in
            completion(result.flatMap { html in Result { try indexLinks(html: html, sourceURL: url) } })
        }
    }

    static func indexLinks(html: String, sourceURL: URL) throws -> [URL] {
        let document = try SwiftSoup.parse(html)
        let anchors = try document.select(".entry-content a[href], #content-section a[href]")
        var seen = Set<String>()
        var urls: [URL] = []
        for anchor in anchors.array() {
            guard let href = try? anchor.attr("href"),
                  let url = URL(string: href, relativeTo: sourceURL)?.absoluteURL,
                  url.host?.lowercased() == sourceURL.host?.lowercased() else { continue }
            let parts = url.path.split(separator: "/")
            let wordpressArticle = parts.count == 4 && parts[0].count == 4 && parts[0].hasPrefix("20") && parts[1].count == 2 && parts[2].count == 2
            let cool18Thread = url.host?.contains("example.invalid") == true &&
                URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "tid" }) == true &&
                url.absoluteString != sourceURL.absoluteString
            guard (wordpressArticle || cool18Thread),
                  seen.insert(url.absoluteString).inserted else { continue }
            urls.append(url)
        }
        guard !urls.isEmpty else { throw ImportFailure.missingContent }
        return urls
    }

    static func validatedURL(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            throw ImportFailure.invalidURL
        }
        return url
    }

    static func extract(html: String, sourceURL: URL) throws -> ImportedBook {
        let document = try SwiftSoup.parse(html)
        guard let title = try document.select("h1.wp-block-post-title, h1.main-title, article h1, h1").first()?.text(),
              !title.isEmpty else { throw ImportFailure.missingContent }
        if let next = try document.select("a[rel=next], .pagination a").first(),
           (try? next.text())?.contains("下一页") == true { throw ImportFailure.unsupportedSite }
        var elements = try document.select(".entry-content.wp-block-post-content > p.wp-block-paragraph")
        if elements.isEmpty() {
            elements = try document.select("article p, .entry-content p, #thread p, .post-content p, .content p")
        }
        var paragraphs: [String] = []
        for element in elements.array() {
            for text in splitLines(atBreaks: element) {
                if text.isEmpty || text.hasPrefix("广告信息：") { continue }
                paragraphs.append(text)
            }
        }
        if (paragraphs.count < 2 || sourceURL.host?.contains("example.invalid") == true),
           let pre = try document.select("#content-section pre, article pre").first() {
            paragraphs = (try pre.text(trimAndNormaliseWhitespace: false)).components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        guard paragraphs.count >= 2 else { throw ImportFailure.missingContent }
        let path = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        guard let slug = path.split(separator: "/").last.map(String.init), !slug.isEmpty else {
            throw ImportFailure.invalidURL
        }
        return ImportedBook(sourceURL: sourceURL.absoluteString,
                            encodedTitle: slug,
                            originalTitle: title,
                            paragraphs: paragraphs)
    }

    private static func splitLines(atBreaks element: Element) -> [String] {
        var lines: [String] = []
        var current = ""
        func flush() {
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lines.append(text) }
            current = ""
        }
        func visit(_ node: Node) {
            if node.nodeName().lowercased() == "br" { flush(); return }
            if let text = node as? TextNode { current += text.getWholeText(); return }
            for child in node.getChildNodes() { visit(child) }
        }
        for child in element.getChildNodes() { visit(child) }
        flush()
        return lines
    }
}
