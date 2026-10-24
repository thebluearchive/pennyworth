/// The selected row of a result list and which rows are on screen. Scrolls in whole
/// rows, just far enough to keep the selection visible.
public struct ResultWindow: Sendable, Equatable {
    public private(set) var count = 0
    /// Rows that fit on screen.
    public private(set) var size: Int
    public private(set) var selection = 0
    /// Index of the top visible row.
    public private(set) var first = 0

    public init(size: Int) {
        self.size = max(size, 1)
    }

    public var visible: Range<Int> { first..<min(first + size, count) }

    /// Starts over with a new list, selecting `selection` (clamped) and scrolled to show it.
    public mutating func reset(count: Int, selection: Int = 0) {
        self.count = max(count, 0)
        self.selection = count == 0 ? 0 : min(max(selection, 0), count - 1)
        first = 0
        reveal()
    }

    public mutating func resize(_ size: Int) {
        self.size = max(size, 1)
        reveal()
    }

    public mutating func moveSelection(by offset: Int) {
        guard count > 0 else { return }
        selection = min(max(selection + offset, 0), count - 1)
        reveal()
    }

    /// Scrolls by whole rows (positive moves down the list), dragging the selection
    /// along if it would leave the screen.
    public mutating func scroll(by rows: Int) {
        guard count > 0 else { return }
        first = clampedFirst(first + rows)
        selection = min(max(selection, visible.lowerBound), visible.upperBound - 1)
    }

    private mutating func reveal() {
        if selection < first {
            first = selection
        } else if selection >= first + size {
            first = selection - size + 1
        }
        first = clampedFirst(first)
    }

    private func clampedFirst(_ first: Int) -> Int {
        min(max(first, 0), max(count - size, 0))
    }
}
