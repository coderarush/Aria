import Foundation

/// A tool the execution layer can drive through the spec §14 lifecycle:
/// `prepare → execute → verify → cleanup`.
///
/// Only ``execute(_:)`` is required; the other stages have safe defaults so
/// simple tools stay terse. Tools are `Sendable` so they can live inside the
/// ``ExecutionEngine`` actor and be handed to the supervisor freely.
protocol ExecutableTool: Sendable {
    /// Stable identifier; matched against ``Domain/Action/tool``.
    var name: String { get }

    /// Optional setup before execution (acquire handles, validate params).
    func prepare(_ action: Domain.Action) async throws

    /// Perform the work, optionally producing an artifact.
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact?

    /// Confirm the action achieved its effect. Return `false` to fail the
    /// action (and trigger a retry) without throwing.
    func verify(_ action: Domain.Action, _ artifact: Domain.Artifact?) async throws -> Bool

    /// Always-runs teardown, on both success and failure.
    func cleanup(_ action: Domain.Action) async
}

extension ExecutableTool {
    func prepare(_ action: Domain.Action) async throws {}
    func verify(_ action: Domain.Action, _ artifact: Domain.Artifact?) async throws -> Bool { true }
    func cleanup(_ action: Domain.Action) async {}
}
