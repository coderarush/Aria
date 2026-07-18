import Foundation

/// The objective dashboard state (spec §58): filterable views over objectives
/// plus search. View state only — no execution.
struct ObjectiveWorkspace: Sendable {

    enum View: String, Sendable { case today, active, waiting, projects, completed }

    var objectives: [Domain.Objective]

    func inView(_ view: View) -> [Domain.Objective] {
        switch view {
        case .today:
            return objectives.filter { $0.status == .active || $0.status == .created }
        case .active:
            return objectives.filter { $0.status == .active }
        case .waiting:
            return objectives.filter { $0.status == .blocked || $0.status == .paused }
        case .completed:
            return objectives.filter { $0.status == .completed }
        case .projects:
            return objectives
        }
    }

    func search(_ query: String) -> [Domain.Objective] {
        let needle = query.lowercased()
        return objectives.filter { $0.title.lowercased().contains(needle) }
    }
}
