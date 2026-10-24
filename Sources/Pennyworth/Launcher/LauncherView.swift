import AppKit
import PennyworthCore
import SwiftUI

struct LauncherView: View {
    let model: LauncherModel
    let onActivate: (Int) -> Void

    var body: some View {
        let theme = model.activeTheme
        let colors = theme.colors
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(colors.accent.color)
                SearchField(
                    text: model.query, placeholder: "Search", theme: theme,
                    focusRequest: model.focusRequest, onChange: model.setQuery)
            }
            .padding(.horizontal, 18)
            .frame(height: LauncherLayout.searchHeight)

            if !model.results.isEmpty {
                Rectangle()
                    .fill(colors.separator.color)
                    .frame(height: 1)
                ResultList(
                    results: model.results, window: model.window, theme: theme,
                    onActivate: onActivate)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(shape.fill(colors.background.color))
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.border.color, lineWidth: theme.borderWidth))
    }
}

/// Shows only the rows in `window`, so the list always scrolls by whole rows.
private struct ResultList: View {
    let results: [SearchResult]
    let window: ResultWindow
    let theme: Theme
    let onActivate: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(window.visible, id: \.self) { index in
                ResultRow(
                    result: results[index], shortcut: index - window.first + 1,
                    isSelected: index == window.selection, theme: theme)
                    .contentShape(Rectangle())
                    .onTapGesture { onActivate(index) }
            }
        }
        .padding(LauncherLayout.listPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) {
            if results.count > window.size {
                ScrollPosition(window: window, color: theme.colors.secondaryText.color)
            }
        }
    }
}

/// A slim indicator of where the visible rows sit in the full list.
private struct ScrollPosition: View {
    let window: ResultWindow
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let track = geometry.size.height
            let thumb = max(track * CGFloat(window.size) / CGFloat(window.count), 12)
            let travel = CGFloat(window.count - window.size)
            let offset = travel > 0 ? (track - thumb) * CGFloat(window.first) / travel : 0
            Capsule()
                .fill(color.opacity(0.35))
                .frame(width: 3, height: thumb)
                .offset(y: offset)
        }
        .frame(width: 3)
        .padding(.vertical, LauncherLayout.listPadding + 4)
        .padding(.trailing, 2)
    }
}

private struct ResultRow: View {
    let result: SearchResult
    /// The ⌘ number for this row (1 is the top visible row); shown for 1–9.
    let shortcut: Int
    let isSelected: Bool
    let theme: Theme

    var body: some View {
        let colors = theme.colors
        let secondary = (isSelected ? colors.selectionSecondaryText : colors.secondaryText).color

        HStack(spacing: 12) {
            ResultIconView(icon: result.icon, tint: colors.accent.color)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if shortcut <= 9 {
                Text("⌘\(shortcut)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: LauncherLayout.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(
                    cornerRadius: max(theme.cornerRadius - LauncherLayout.listPadding, 4),
                    style: .continuous)
                    .fill(colors.selectionBackground.color)
            }
        }
    }

    /// The title with characters that matched the query drawn in the match color.
    private var title: AttributedString {
        let colors = theme.colors
        let base = (isSelected ? colors.selectionText : colors.text).color
        let matches = Set(result.titleMatches)
        var attributed = AttributedString()
        var run = ""
        var runIsMatch = false

        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            piece.foregroundColor = runIsMatch ? colors.match.color : base
            attributed += piece
            run = ""
        }
        for (offset, character) in result.title.enumerated() {
            let isMatch = matches.contains(offset)
            if isMatch != runIsMatch {
                flush()
                runIsMatch = isMatch
            }
            run.append(character)
        }
        flush()
        return attributed
    }
}

private struct ResultIconView: View {
    let icon: ResultIcon
    let tint: Color

    var body: some View {
        switch icon {
        case .none:
            Color.clear
        case .file(let url):
            Image(nsImage: IconCache.shared.icon(for: url))
                .resizable()
                .interpolation(.high)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 20))
                .foregroundStyle(tint)
        case .palette(let colors):
            PaletteIcon(colors: colors)
        }
    }
}

/// A rounded tile in a theme's background color with a column of its accent colors.
private struct PaletteIcon: View {
    let colors: [RGBAColor]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        ZStack {
            shape.fill((colors.first ?? RGBAColor(red: 0, green: 0, blue: 0)).color)
            HStack(spacing: 3) {
                ForEach(Array(colors.dropFirst().enumerated()), id: \.offset) { _, color in
                    Capsule().fill(color.color).frame(width: 4, height: 16)
                }
            }
        }
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .padding(1)
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for url: URL) -> NSImage {
        if let cached = cache.object(forKey: url.path as NSString) { return cached }
        // Resolve symlinks (e.g. Safari) so the icon has no alias badge.
        let icon = NSWorkspace.shared.icon(forFile: url.resolvingSymlinksInPath().path)
        cache.setObject(icon, forKey: url.path as NSString)
        return icon
    }
}

extension RGBAColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
