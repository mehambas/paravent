import Foundation
import CoreGraphics

public enum MenuBarMatch {
    /// Status windows include a little horizontal padding around their AX button.
    /// Overlapping overlays must never consume the button's identity.
    public static func accepts(window: CGRect, button: CGRect, sameOwner: Bool, systemHost: Bool) -> Bool {
        guard sameOwner || systemHost, button.width > 0, button.height > 0,
              window.width > 0, window.height > 0, window.height <= 50 else { return false }
        return window.insetBy(dx: -1, dy: -1).contains(button)
            && abs(window.midX - button.midX) <= 2
            && abs(window.midY - button.midY) <= 2
            && window.width - button.width <= 32
            && window.height - button.height <= 24
    }
}
