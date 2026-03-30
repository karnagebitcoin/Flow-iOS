import SwiftUI

struct AppThemePalette {
    let background: Color
    let chromeBackground: Color
    let secondaryBackground: Color
    let groupedBackground: Color
    let secondaryGroupedBackground: Color
    let secondaryFill: Color
    let tertiaryFill: Color
    let separator: Color

    static let system = AppThemePalette(
        background: Color(.systemBackground),
        chromeBackground: Color(.systemBackground),
        secondaryBackground: Color(.secondarySystemBackground),
        groupedBackground: Color(.systemGroupedBackground),
        secondaryGroupedBackground: Color(.secondarySystemGroupedBackground),
        secondaryFill: Color(.secondarySystemFill),
        tertiaryFill: Color(.tertiarySystemFill),
        separator: Color(.separator)
    )

    static let black = AppThemePalette(
        background: Color(red: 0.03, green: 0.03, blue: 0.04),
        chromeBackground: Color(red: 0.05, green: 0.05, blue: 0.06),
        secondaryBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        groupedBackground: Color(red: 0.06, green: 0.06, blue: 0.08),
        secondaryGroupedBackground: Color(red: 0.12, green: 0.12, blue: 0.14),
        secondaryFill: Color.white.opacity(0.10),
        tertiaryFill: Color.white.opacity(0.06),
        separator: Color.white.opacity(0.16)
    )

    static let white = AppThemePalette(
        background: Color.white,
        chromeBackground: Color.white,
        secondaryBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        groupedBackground: Color(red: 0.98, green: 0.98, blue: 0.985),
        secondaryGroupedBackground: Color(red: 0.955, green: 0.955, blue: 0.965),
        secondaryFill: Color.black.opacity(0.08),
        tertiaryFill: Color.black.opacity(0.05),
        separator: Color.black.opacity(0.12)
    )

    static let sakura = AppThemePalette(
        background: Color(red: 1.0, green: 0.985, blue: 0.994),
        chromeBackground: Color(red: 1.0, green: 0.991, blue: 0.997),
        secondaryBackground: Color(red: 0.994, green: 0.954, blue: 0.987),
        groupedBackground: Color(red: 0.995, green: 0.968, blue: 0.992),
        secondaryGroupedBackground: Color(red: 0.988, green: 0.945, blue: 0.981),
        secondaryFill: Color(red: 1.0, green: 0.404, blue: 0.941).opacity(0.14),
        tertiaryFill: Color(red: 0.976, green: 0.659, blue: 1.0).opacity(0.18),
        separator: Color(red: 1.0, green: 0.404, blue: 0.941).opacity(0.18)
    )
}
