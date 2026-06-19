import Foundation

/// Minimal description of a tool for building a Gemini functionDeclaration.
struct ToolSpec {
    let name: String
    let description: String
    let params: [String: String]   // paramName : human description
}

/// Builds Gemini `functionDeclarations` (JSON-serializable dictionaries).
enum ToolDeclarations {
    static func declarations(for specs: [ToolSpec]) -> [[String: Any]] {
        specs.map { spec in
            var properties: [String: Any] = [:]
            for (k, desc) in spec.params {
                properties[k] = ["type": "string", "description": desc]
            }
            return [
                "name": spec.name,
                "description": spec.description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                ]
            ]
        }
    }
}
