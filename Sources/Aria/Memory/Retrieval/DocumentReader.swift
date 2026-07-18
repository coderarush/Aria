import Foundation
import PDFKit

enum DocumentReaderError: Error, Equatable {
    case unsupportedType(String)
    case fileNotFound
    case extractionFailed
}

struct DocumentReader: Sendable {
    func extract(path: String, maxChars: Int = 8000) async throws -> String {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw DocumentReaderError.fileNotFound
        }

        let ext = url.pathExtension.lowercased()
        let extracted: String

        switch ext {
        case "pdf":
            guard let doc = PDFDocument(url: url) else {
                throw DocumentReaderError.extractionFailed
            }
            var pages: [String] = []
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) {
                    pages.append(page.string ?? "")
                }
            }
            extracted = pages.joined(separator: "\n")

        case "txt", "md":
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                throw DocumentReaderError.extractionFailed
            }
            extracted = content

        case "rtf":
            guard let attrStr = try? NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) else {
                throw DocumentReaderError.extractionFailed
            }
            extracted = attrStr.string

        default:
            throw DocumentReaderError.unsupportedType(ext)
        }

        return String(extracted.prefix(maxChars))
    }

    func summarize(
        text: String,
        query: String?,
        synthesize: @Sendable (String) async throws -> String
    ) async throws -> String {
        let prompt: String
        if let query = query, !query.isEmpty {
            prompt = "Summarize this document focusing on: \(query). Be concise (5-8 sentences).\n\nDocument:\n\(text)"
        } else {
            prompt = "Give an executive summary of this document covering main points, key arguments, conclusions. 5-8 sentences.\n\nDocument:\n\(text)"
        }
        return try await synthesize(prompt)
    }
}
