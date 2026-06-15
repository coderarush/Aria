import Foundation

struct DocReadTool: AriaTool {
    static let name = "doc_read"
    static let description = "Extract text from a file (PDF, TXT, MD, RTF). Input: path (absolute path to file). Returns first 500 chars + total length."
    static let paramHints: [String: String] = [
        "path": "Absolute path to the file to read."
    ]

    private let reader: DocumentReader

    init(reader: DocumentReader = DocumentReader()) {
        self.reader = reader
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let path = input["path"], !path.isEmpty else {
            return .fail("Missing input: path")
        }
        do {
            let text = try await reader.extract(path: path)
            return .ok("\(text.prefix(500))...\n[Total: \(text.count) characters extracted]")
        } catch DocumentReaderError.fileNotFound {
            return .fail("File not found: \(path)")
        } catch DocumentReaderError.unsupportedType(let ext) {
            return .fail("Unsupported file type: .\(ext). Supported: PDF, TXT, MD, RTF.")
        } catch DocumentReaderError.extractionFailed {
            return .fail("Failed to extract text from file.")
        } catch {
            return .fail("Error reading file: \(error.localizedDescription)")
        }
    }
}

struct DocSummarizeTool: AriaTool {
    static let name = "doc_summarize"
    static let description = "Summarize a document. Input: path (absolute path), optional query (what to focus on)."
    static let paramHints: [String: String] = [
        "path": "Absolute path to the file to summarize.",
        "query": "Optional: what aspect to focus the summary on."
    ]

    private let gemini: GeminiClient
    private let reader: DocumentReader

    init(gemini: GeminiClient = GeminiClient(), reader: DocumentReader = DocumentReader()) {
        self.gemini = gemini
        self.reader = reader
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let path = input["path"], !path.isEmpty else {
            return .fail("Missing input: path")
        }
        let query = input["query"]
        do {
            let text = try await reader.extract(path: path)
            let summary = try await reader.summarize(text: text, query: query) { [gemini] prompt in
                try await gemini.generateText(prompt: prompt, temperature: 0.3)
            }
            return .ok(summary)
        } catch {
            return .ok("Error: \(error)")
        }
    }
}
