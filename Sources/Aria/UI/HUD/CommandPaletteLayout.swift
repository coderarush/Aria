import Foundation

struct CommandPaletteLayout: Equatable, Sendable {
    let width: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    let maxVisibleRecents: Int

    static let compact = Self(
        width: 500,
        rowHeight: 30,
        headerHeight: 64,
        maxVisibleRecents: 4
    )

    func visibleCommands(_ commands: [String]) -> [String] {
        Array(commands.prefix(maxVisibleRecents))
    }

    func contentHeight(recentCount: Int) -> CGFloat {
        let visible = min(max(0, recentCount), maxVisibleRecents)
        let listHeight: CGFloat = visible == 0
            ? 24
            : CGFloat(visible) * (rowHeight + 2) + 38
        return headerHeight + listHeight
    }
}
