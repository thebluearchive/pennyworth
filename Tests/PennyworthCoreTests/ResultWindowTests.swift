import Testing
@testable import PennyworthCore

@Suite struct ResultWindowTests {
    private func window(count: Int, size: Int = 3, selection: Int = 0) -> ResultWindow {
        var window = ResultWindow(size: size)
        window.reset(count: count, selection: selection)
        return window
    }

    @Test func startsAtTheTop() {
        let window = window(count: 10)
        #expect(window.visible == 0..<3)
        #expect(window.selection == 0)
    }

    @Test func scrollsOneRowAtATimeOnlyWhenTheSelectionLeaves() {
        var window = window(count: 10)
        window.moveSelection(by: 2)
        #expect(window.visible == 0..<3)
        window.moveSelection(by: 1)
        #expect(window.visible == 1..<4)
        #expect(window.selection == 3)

        window.moveSelection(by: -1)
        window.moveSelection(by: -1)
        #expect(window.visible == 1..<4)
        window.moveSelection(by: -1)
        #expect(window.visible == 0..<3)
    }

    @Test func stopsAtTheEnds() {
        var window = window(count: 5)
        window.moveSelection(by: -1)
        #expect(window.selection == 0)
        window.moveSelection(by: 100)
        #expect(window.selection == 4)
        #expect(window.visible == 2..<5)
    }

    @Test func wheelScrollingDragsTheSelectionAlong() {
        var window = window(count: 10)
        window.scroll(by: 2)
        #expect(window.visible == 2..<5)
        #expect(window.selection == 2)

        window.moveSelection(by: 2)
        window.scroll(by: -1)
        #expect(window.visible == 1..<4)
        #expect(window.selection == 3)

        window.scroll(by: 100)
        #expect(window.visible == 7..<10)
        window.scroll(by: -100)
        #expect(window.visible == 0..<3)
        #expect(window.selection == 2)
    }

    @Test func resetRevealsAKeptSelection() {
        let window = window(count: 10, selection: 8)
        #expect(window.visible == 6..<9)
        #expect(window.selection == 8)
    }

    @Test func handlesShortAndEmptyLists() {
        var short = window(count: 2)
        short.scroll(by: 1)
        #expect(short.visible == 0..<2)

        var empty = window(count: 0)
        empty.moveSelection(by: 1)
        empty.scroll(by: 1)
        #expect(empty.visible.isEmpty)
        #expect(empty.selection == 0)
    }

    @Test func resizingKeepsTheSelectionVisible() {
        var window = window(count: 10, size: 5)
        window.moveSelection(by: 4)
        window.resize(2)
        #expect(window.visible == 3..<5)
    }
}
