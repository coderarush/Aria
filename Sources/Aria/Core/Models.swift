import Foundation

/// Structured response Aria expects back from Gemini. The protocol is real
/// from day 1 even though the slice only acts on `.answer` / `.clarify`.
struct AriaResponse: Codable, Equatable {
    enum Kind: String, Codable {
        case answer
        case action
        case multiAction = "multi_action"
        case clarify
    }

    let type: Kind
    let message: String
    let confidence: Double
    let actions: [AgentAction]
    let followup: String?

    /// Whether the turn actually completed — set by the orchestrator from the
    /// real execution outcome, NOT reported by the model. Transient (never
    /// encoded): a decoded model response defaults to true and the orchestrator
    /// overrides it on a failed/declined/capped turn. Used by the learning loop
    /// so a failing automation is recorded as a failure (see PatternEngine).
    var succeeded: Bool = true

    init(type: Kind,
         message: String,
         confidence: Double = 1.0,
         actions: [AgentAction] = [],
         followup: String? = nil,
         succeeded: Bool = true) {
        self.type = type
        self.message = message
        self.confidence = confidence
        self.actions = actions
        self.followup = followup
        self.succeeded = succeeded
    }

    /// A turn succeeds only when it completed: a clarify (needs the user) or a
    /// turn whose action failed or was declined did not.
    static func turnSucceeded(type: Kind, executionFailed: Bool) -> Bool {
        type != .clarify && !executionFailed
    }

    private enum CodingKeys: String, CodingKey {
        case type, message, confidence, actions, followup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(Kind.self, forKey: .type)
        message = try c.decode(String.self, forKey: .message)
        // Be lenient: Gemini sometimes omits confidence/actions.
        confidence = (try? c.decode(Double.self, forKey: .confidence)) ?? 1.0
        actions = (try? c.decode([AgentAction].self, forKey: .actions)) ?? []
        followup = try? c.decodeIfPresent(String.self, forKey: .followup)
    }
}

/// A single requested action. In the slice these are parsed but routed to a
/// "not yet implemented" stub; later passes map `tool` to real AriaTools.
struct AgentAction: Codable, Equatable {
    let tool: String
    let input: [String: String]

    init(tool: String, input: [String: String] = [:]) {
        self.tool = tool
        self.input = input
    }
}

/// One turn of conversation, persisted to disk.
struct ConversationTurn: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let transcript: String
    let responseMessage: String
    let responseType: AriaResponse.Kind

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         transcript: String,
         responseMessage: String,
         responseType: AriaResponse.Kind) {
        self.id = id
        self.timestamp = timestamp
        self.transcript = transcript
        self.responseMessage = responseMessage
        self.responseType = responseType
    }
}
