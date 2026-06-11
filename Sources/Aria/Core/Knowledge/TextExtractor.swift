import Foundation
import PDFKit

/// Pulls plain text out of the file types the Knowledge Engine indexes.
/// Local-only: nothing leaves the machine. Unsupported or unreadable files
/// return nil and are skipped silently by the indexer.
enum TextExtractor {

    /// Plain-text-ish extensions read directly.
    static let textExtensions: Set<String> = [
        "md", "txt", "markdown", "rtf", "csv", "json", "yaml", "yml", "xml", "html",
        "swift", "py", "js", "ts", "jsx", "tsx", "go", "rs", "rb", "java", "kt",
        "c", "h", "cpp", "hpp", "m", "mm", "sh", "zsh", "sql", "toml", "cfg", "ini", "log"
    ]

    static func isIndexable(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || textExtensions.contains(ext)
    }

    static func extract(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return extractPDF(url) }
        guard textExtensions.contains(ext) else { return nil }
        guard let data = try? Data(contentsOf: url), data.count < 4_000_000 else { return nil }
        if ext == "rtf" {
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        }
        return String(data: data, encoding: .utf8)
    }

    /// PDFKit text layer. Image-only PDFs yield nil (no OCR — keep it fast and
    /// dependency-free; OCR is a later upgrade).
    private static func extractPDF(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var out = ""
        for i in 0..<min(doc.pageCount, 200) {
            if let page = doc.page(at: i), let s = page.string { out += s + "\n" }
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Splits document text into search-sized chunks, preferring paragraph
/// boundaries so snippets read naturally.
enum Chunker {
    static func chunks(of text: String, target: Int = 800) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > target else { return [trimmed] }

        var result: [String] = []
        var current = ""
        for para in trimmed.components(separatedBy: "\n\n") {
            let p = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { continue }
            if current.isEmpty {
                current = p
            } else if current.count + p.count + 2 <= target {
                current += "\n\n" + p
            } else {
                result.append(current)
                current = p
            }
            // A single paragraph far past target gets hard-split.
            while current.count > target + (target / 2) {
                let idx = current.index(current.startIndex, offsetBy: target)
                result.append(String(current[..<idx]))
                current = String(current[idx...])
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
