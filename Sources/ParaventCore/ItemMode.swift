import Foundation

/// Where a menu bar icon lives: in the menu bar, behind the divider and in the panel, or behind the divider only.
public enum ItemMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case visible, panel, hidden

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Drawer, as Paravent was called before its first release, saved the panel mode as "drawer".
        self = raw == "drawer" ? .panel : ItemMode(rawValue: raw) ?? .visible
    }
}
