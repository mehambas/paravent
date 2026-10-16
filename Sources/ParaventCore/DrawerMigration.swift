import Foundation

/// Paravent was called Drawer before its first release. On the first launch it copies Drawer's folder and settings,
/// so the icons keep their places; Drawer's own files are left as they are.
public enum DrawerMigration {
    public static let oldDomain = "com.hamzabasaran.drawer"
    public static let oldFolderName = "Drawer"
    static let marker = "migratedFromDrawer"

    /// Copies `old` to `new` unless `new` already exists. Returns whether it copied.
    @discardableResult
    public static func copyFolder(from old: URL, to new: URL, fileManager: FileManager = .default) -> Bool {
        guard !fileManager.fileExists(atPath: new.path), fileManager.fileExists(atPath: old.path) else { return false }
        return (try? fileManager.copyItem(at: old, to: new)) != nil
    }

    /// Copies the old settings once, without overwriting any Paravent already has. The status items' positions are
    /// stored under their autosave names, which were drawer.main and drawer.divider.
    public static func copyDefaults(_ old: [String: Any]?, to defaults: UserDefaults) {
        guard defaults.object(forKey: marker) == nil else { return }
        for (key, value) in old ?? [:] {
            let renamed = key.replacingOccurrences(of: " drawer.", with: " paravent.")
            if defaults.object(forKey: renamed) == nil { defaults.set(value, forKey: renamed) }
        }
        defaults.set(true, forKey: marker)
    }
}
