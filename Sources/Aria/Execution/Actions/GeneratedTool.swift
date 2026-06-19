import Foundation

enum ToolLanguage: String, Codable, CaseIterable {
    case python, bash, javascript, applescript
}

enum ToolSource: String, Codable {
    case generated, community, builtin
}

/// A self-contained script Aria wrote (or imported) to accomplish a task.
/// Persisted as JSON under Application Support/Aria/tools/.
struct GeneratedTool: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String
    let language: ToolLanguage
    let code: String
    let createdAt: Date
    var usageCount: Int
    let source: ToolSource

    init(id: UUID = UUID(),
         name: String,
         description: String,
         language: ToolLanguage,
         code: String,
         createdAt: Date = Date(),
         usageCount: Int = 0,
         source: ToolSource = .generated) {
        self.id = id
        self.name = name
        self.description = description
        self.language = language
        self.code = code
        self.createdAt = createdAt
        self.usageCount = usageCount
        self.source = source
    }
}
