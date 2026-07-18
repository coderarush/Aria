import Foundation

/// What kind of thing the user circled — so the Lens asks the right question. An
/// error wants "what's wrong + how to fix"; code wants "what does this do"; a math
/// expression wants the answer; everything else wants a plain explanation. Pure +
/// testable; runs on the on-device OCR text before any model call.
enum LensContentKind: Equatable {
    case error, code, math, prose
}

enum LensClassifier {
    private static let errorSignals = [
        "error", "exception", "traceback", "stack trace", "stacktrace", "failed",
        "failure", "fatal", "undefined", "null pointer", "nullpointer", "segmentation",
        "errno", "warning:", "panic", "cannot find", "is not defined", "unexpected token",
        "syntaxerror", "typeerror", "referenceerror", "nameerror", " err ", "exit code"
    ]
    private static let codeSignals = [
        "func ", "def ", "class ", "import ", "const ", "=> ", "return ", "public ",
        "private ", "#include", "function ", "println", "console.log", "</", "/>",
        "() {", ");", "};", "&&", "||", "::", "<-"
    ]

    static func kind(of text: String) -> LensContentKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .prose }
        let lower = trimmed.lowercased()

        if errorSignals.contains(where: { lower.contains($0) }) { return .error }

        let codeHits = codeSignals.filter { lower.contains($0) }.count
        if codeHits >= 2 { return .code }

        if looksLikeMath(trimmed) { return .math }

        return .prose
    }

    /// Mostly digits + math operators, short, and contains an operator or '=' — a
    /// circled expression to solve, not prose with a stray number.
    private static func looksLikeMath(_ text: String) -> Bool {
        guard text.count <= 80 else { return false }
        let mathOps = CharacterSet(charactersIn: "+-*/=^%×÷√")
        guard text.rangeOfCharacter(from: mathOps) != nil else { return false }
        let digits = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return digits >= 1 && digits >= letters
    }

    /// The instruction to send the model for `kind`, given the recognized `ocr`.
    static func prompt(for kind: LensContentKind, ocr: String) -> String {
        let body = String(ocr.prefix(1400))
        let snippet = "\"\"\"\n\(body)\n\"\"\""
        switch kind {
        case .error:
            return """
            The user circled this error/warning on their Mac screen:
            \(snippet)
            In 1–3 short sentences: say plainly what it means, then the single most likely \
            fix. Be concrete and actionable. No preamble.
            """
        case .code:
            return """
            The user circled this code on their screen:
            \(snippet)
            In 1–3 short sentences, explain what it does. If something looks wrong, say so. \
            No preamble.
            """
        case .math:
            return """
            The user circled this expression/problem on their screen:
            \(snippet)
            Give the answer, then one short line of how. No preamble.
            """
        case .prose:
            return """
            The user circled this on their Mac screen:
            \(snippet)
            In 1–3 short, plain sentences, explain what it is or means and what to do with \
            it. If it's a control/label, say what it does. No preamble.
            """
        }
    }
}
