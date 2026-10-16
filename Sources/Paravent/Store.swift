import AppKit
import ApplicationServices
import ParaventCore

extension ItemMode {
    var label: String {
        switch self {
        case .visible: String(localized: "Shown")
        case .panel: String(localized: "In Panel")
        case .hidden: String(localized: "Hidden")
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var items: [BarItem] = []
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var permissionsGranted = true
    @Published var isApplying = false
    @Published var notes: [String] = []
    @Published private(set) var modes: [String: ItemMode] = [:]

    private let configURL: URL?
    private let iconsDir: URL?

    nonisolated static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Paravent", isDirectory: true)

    /// Without a folder the store reads and writes nothing, for the demo and the visual check.
    init(folder: URL?) {
        guard let folder else {
            configURL = nil
            iconsDir = nil
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        configURL = folder.appendingPathComponent("config.json")
        let iconsDir = folder.appendingPathComponent("icons", isDirectory: true)
        self.iconsDir = iconsDir
        try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        loadCachedIcons()
        if let configURL, let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode([String: ItemMode].self, from: data) {
            modes = decoded
        }
    }

    func showSamples(_ items: [BarItem], images: [String: NSImage], modes: [String: ItemMode]) {
        self.items = items
        self.images = images
        self.modes = modes
    }

    var panelItems: [BarItem] { items.filter { mode(of: $0) == .panel } }

    func mode(of item: BarItem) -> ItemMode { item.isPinned ? .visible : modes[item.id] ?? .visible }

    func setMode(_ mode: ItemMode, for item: BarItem) {
        migrateLegacyMode(to: item)
        modes[item.id] = mode
        persistModes()
    }

    func refresh() async {
        guard configURL != nil else { return }
        permissionsGranted = AXIsProcessTrusted() && CGPreflightScreenCaptureAccess()
        let started = Date()
        let rowTop = MenuBarScanner.rowTop(for: NSEvent.mouseLocation)
        let scanned = await Task.detached { MenuBarScanner.scan(preferredRowTop: rowTop) }.value
        Log.write("scan: \(scanned.count) items in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        migrateLegacyModes(for: scanned)
        items = scanned
        for (id, cg) in await IconCapture.capture(scanned) {
            let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
            images[id] = image
            if let url = iconURL(for: id), let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: url, options: .atomic)
            }
        }
    }

    private func migrateLegacyModes(for scanned: [BarItem]) {
        let byBundle = Dictionary(grouping: scanned, by: \.bundleID)
        var changed = false
        for item in scanned where item.id.contains("/id-") && byBundle[item.bundleID]?.count == 1 {
            changed = migrateLegacyMode(to: item) || changed
        }
        if changed { persistModes() }
    }

    @discardableResult
    private func migrateLegacyMode(to item: BarItem) -> Bool {
        guard item.id.contains("/id-"), modes[item.id] == nil else { return false }
        let prefix = item.bundleID + "/"
        let legacyKeys = modes.keys.filter { $0.hasPrefix(prefix) && !$0.contains("/id-") }
        guard legacyKeys.count == 1, let oldKey = legacyKeys.first,
              let value = modes.removeValue(forKey: oldKey) else { return false }
        modes[item.id] = value
        return true
    }

    private func persistModes() {
        if let configURL, let data = try? JSONEncoder().encode(modes) { try? data.write(to: configURL, options: .atomic) }
    }

    private func iconURL(for id: String) -> URL? {
        iconsDir?.appendingPathComponent((id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id) + ".png")
    }

    private func loadCachedIcons() {
        guard let iconsDir else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: iconsDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "png" {
            guard let id = file.deletingPathExtension().lastPathComponent.removingPercentEncoding,
                  let data = try? Data(contentsOf: file),
                  let rep = NSBitmapImageRep(data: data) else { continue }
            let image = NSImage(size: NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2))
            image.addRepresentation(rep)
            images[id] = image
        }
    }
}
