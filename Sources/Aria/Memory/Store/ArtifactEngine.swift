import Foundation

/// One version of an artifact's content (spec §97).
struct ArtifactVersion: Sendable {
    let version: Int
    let content: String
    let createdAt: Date
}

/// A first-class, versioned output (spec §97).
struct VersionedArtifact: Identifiable, Sendable {
    enum Kind: String, Sendable { case document, task, code, plan, communication, memory }
    let id: UUID
    var kind: Kind
    var versions: [ArtifactVersion]

    var current: ArtifactVersion? { versions.last }
}

/// Makes outputs first-class (spec §97): version, restore, compare, reuse.
actor ArtifactEngine {

    private var artifacts: [UUID: VersionedArtifact] = [:]

    @discardableResult
    func create(kind: VersionedArtifact.Kind, content: String) -> VersionedArtifact {
        let artifact = VersionedArtifact(
            id: UUID(), kind: kind,
            versions: [ArtifactVersion(version: 1, content: content, createdAt: Date())])
        artifacts[artifact.id] = artifact
        return artifact
    }

    func get(_ id: UUID) -> VersionedArtifact? { artifacts[id] }

    func update(_ id: UUID, content: String) {
        guard var artifact = artifacts[id] else { return }
        let next = (artifact.versions.last?.version ?? 0) + 1
        artifact.versions.append(ArtifactVersion(version: next, content: content, createdAt: Date()))
        artifacts[id] = artifact
    }

    /// Restore an earlier version by appending a copy as the new current.
    func restore(_ id: UUID, to version: Int) {
        guard var artifact = artifacts[id],
              let old = artifact.versions.first(where: { $0.version == version }) else { return }
        let next = (artifact.versions.last?.version ?? 0) + 1
        artifact.versions.append(ArtifactVersion(version: next, content: old.content, createdAt: Date()))
        artifacts[id] = artifact
    }

    /// Whether two versions have identical content.
    func compare(_ id: UUID, _ a: Int, _ b: Int) -> Bool {
        guard let artifact = artifacts[id],
              let va = artifact.versions.first(where: { $0.version == a }),
              let vb = artifact.versions.first(where: { $0.version == b }) else { return false }
        return va.content == vb.content
    }
}
