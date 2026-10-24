import Foundation

extension Theme {
    public static let defaultID = "tokyo-night"

    /// Built-in themes. Tokyo Night colors follow folke/tokyonight.nvim.
    public static let builtIn: [Theme] = [
        tokyoNight, tokyoNightStorm, tokyoNightMoon, tokyoNightDay,
        catppuccinMocha, dracula, nord,
    ]

    public static let tokyoNight = Theme(
        id: "tokyo-night", name: "Tokyo Night", appearance: .dark,
        colors: Colors(
            background: "#1a1b26", border: "#27a1b9", separator: "#3b4261",
            text: "#c0caf5", secondaryText: "#737aa2", placeholder: "#565f89",
            accent: "#7aa2f7", match: "#ff9e64",
            selectionBackground: "#283457", selectionText: "#c0caf5",
            selectionSecondaryText: "#a9b1d6"))

    public static let tokyoNightStorm = Theme(
        id: "tokyo-night-storm", name: "Tokyo Night Storm", appearance: .dark,
        colors: Colors(
            background: "#24283b", border: "#29a4bd", separator: "#3b4261",
            text: "#c0caf5", secondaryText: "#737aa2", placeholder: "#565f89",
            accent: "#7aa2f7", match: "#ff9e64",
            selectionBackground: "#2e3c64", selectionText: "#c0caf5",
            selectionSecondaryText: "#a9b1d6"))

    public static let tokyoNightMoon = Theme(
        id: "tokyo-night-moon", name: "Tokyo Night Moon", appearance: .dark,
        colors: Colors(
            background: "#222436", border: "#589ed7", separator: "#3b4261",
            text: "#c8d3f5", secondaryText: "#828bb8", placeholder: "#636da6",
            accent: "#82aaff", match: "#ff966c",
            selectionBackground: "#2d3f76", selectionText: "#c8d3f5",
            selectionSecondaryText: "#c8d3f5b3"))

    public static let tokyoNightDay = Theme(
        id: "tokyo-night-day", name: "Tokyo Night Day", appearance: .light,
        colors: Colors(
            background: "#e1e2e7", border: "#a8aecb", separator: "#c4c8da",
            text: "#3760bf", secondaryText: "#6172b0", placeholder: "#848cb5",
            accent: "#2e7de9", match: "#b15c00",
            selectionBackground: "#b7c1e3", selectionText: "#3760bf",
            selectionSecondaryText: "#6172b0"))

    public static let catppuccinMocha = Theme(
        id: "catppuccin-mocha", name: "Catppuccin Mocha", appearance: .dark,
        colors: Colors(
            background: "#1e1e2e", border: "#b4befe", separator: "#313244",
            text: "#cdd6f4", secondaryText: "#a6adc8", placeholder: "#6c7086",
            accent: "#cba6f7", match: "#fab387",
            selectionBackground: "#45475a", selectionText: "#cdd6f4",
            selectionSecondaryText: "#bac2de"))

    public static let dracula = Theme(
        id: "dracula", name: "Dracula", appearance: .dark,
        colors: Colors(
            background: "#282a36", border: "#bd93f9", separator: "#44475a",
            text: "#f8f8f2", secondaryText: "#f8f8f299", placeholder: "#6272a4",
            accent: "#bd93f9", match: "#ff79c6",
            selectionBackground: "#44475a", selectionText: "#f8f8f2",
            selectionSecondaryText: "#f8f8f2b3"))

    public static let nord = Theme(
        id: "nord", name: "Nord", appearance: .dark,
        colors: Colors(
            background: "#2e3440", border: "#88c0d0", separator: "#3b4252",
            text: "#eceff4", secondaryText: "#d8dee999", placeholder: "#616e88",
            accent: "#88c0d0", match: "#ebcb8b",
            selectionBackground: "#434c5e", selectionText: "#eceff4",
            selectionSecondaryText: "#d8dee9b3"))
}

extension RGBAColor: ExpressibleByStringLiteral {
    /// For built-in palettes only; traps on malformed literals.
    public init(stringLiteral value: String) {
        guard let color = RGBAColor(hex: value) else {
            preconditionFailure("Invalid color literal \(value)")
        }
        self = color
    }
}
