import AppKit
import ParaventCore
import SwiftUI

/// `--capture-demo <folder>` renders the README animation's frames, `--capture-previews <folder>` the panel and
/// both settings tabs. Both draw sample icons on a stand-in menu bar: they never scan, move or capture the real one,
/// and read and write no settings.
struct Capture {
    enum Kind { case demo, previews }
    let kind: Kind
    let output: URL

    init?(arguments: [String]) {
        for (flag, kind) in [("--capture-demo", Kind.demo), ("--capture-previews", .previews)] {
            guard let index = arguments.firstIndex(of: flag) else { continue }
            guard arguments.count > index + 1 else {
                print("Usage: Paravent \(flag) <output-directory>")
                exit(2)
            }
            self.kind = kind
            output = URL(fileURLWithPath: arguments[index + 1])
            return
        }
        return nil
    }
}

@MainActor
final class CaptureDelegate: NSObject, NSApplicationDelegate {
    private let capture: Capture

    init(capture: Capture) { self.capture = capture }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                switch capture.kind {
                case .demo: try await DemoStage.captureDemo(to: capture.output)
                case .previews: try await DemoStage.capturePreviews(to: capture.output)
                }
                exit(0)
            } catch {
                fputs("Capture failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }
}

private struct CaptureError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private struct Sample {
    let id: String
    let name: String
    let symbol: String
    let mode: ItemMode
}

@MainActor
private final class DemoStage {
    static let canvas = CGSize(width: 960, height: 600)
    static let scale: CGFloat = 2
    static let barHeight: CGFloat = 24
    private static let slot: CGFloat = 30
    private static let dividerSlot: CGFloat = 16

    /// Left to right, as they sit left of the system icons. The demo moves Backup into the panel.
    private static let samples = [
        Sample(id: "com.example.cloud/0", name: "Cloud Drive", symbol: "icloud", mode: .panel),
        Sample(id: "com.example.vpn/0", name: "VPN", symbol: "lock.shield", mode: .panel),
        Sample(id: "com.example.clipboard/0", name: "Clipboard", symbol: "list.clipboard", mode: .panel),
        Sample(id: "com.example.colors/0", name: "Color Picker", symbol: "eyedropper", mode: .panel),
        Sample(id: "com.example.stats/0", name: "System Stats", symbol: "cpu", mode: .hidden),
        Sample(id: "com.example.keys/0", name: "Key Remapper", symbol: "keyboard", mode: .hidden),
        Sample(id: "com.example.backup/0", name: "Backup", symbol: "clock.arrow.circlepath", mode: .visible),
        Sample(id: "com.example.timer/0", name: "Timer", symbol: "timer", mode: .visible),
    ]
    private static let systemSymbols = ["battery.75percent", "wifi", "switch.2"]

    private let dark: Bool
    private let store = Store(folder: nil)
    private let updater = Updater(active: false)
    private let selection = SettingsSelection()
    private var frames: [(name: String, seconds: Double)] = []
    private var folder: URL?

    init(dark: Bool) {
        self.dark = dark
        let items = Self.samples.enumerated().map { index, sample in
            BarItem(id: sample.id, name: sample.name, bundleID: String(sample.id.prefix { $0 != "/" }), windowID: 0, pid: 0,
                    frame: CGRect(x: CGFloat(index) * Self.slot, y: 0, width: Self.slot, height: Self.barHeight), axElement: nil)
        }
        let images = Dictionary(uniqueKeysWithValues: Self.samples.map { ($0.id, Self.glyph($0.symbol, color: .white, size: 15)) })
        store.showSamples(items, images: images, modes: Dictionary(uniqueKeysWithValues: Self.samples.map { ($0.id, $0.mode) }))
    }

    // MARK: Demo

    static func captureDemo(to output: URL) async throws {
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let folder = output.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stage = DemoStage(dark: name == "dark")
            stage.folder = folder
            try await stage.playDemo()
            try stage.finish()
        }
        print("Demo frames: \(output.path)/dark, \(output.path)/light")
    }

    private func playDemo() async throws {
        let backup = "com.example.backup/0", clipboard = "com.example.clipboard/0"
        var applied = store.modes
        var scene = Scene(modes: applied)
        scene.pointer = CGPoint(x: 380, y: 300)
        try add(scene, seconds: 1.4)

        scene.settings = try await settingsImage()
        scene.pointer = CGPoint(x: 330, y: 360)
        try add(scene, seconds: 0.9)
        let settingsOrigin = settingsOrigin(scene.settings!)
        let backupRow = CGFloat(Self.samples.firstIndex { $0.id == backup }!)
        let inPanel = CGPoint(x: settingsOrigin.x + scene.settings!.size.width - 137, y: settingsOrigin.y + 132 + backupRow * 52)
        try await move(&scene, to: inPanel)
        store.setMode(.panel, for: store.items.first { $0.id == backup }!)
        scene.settings = try await settingsImage()
        try add(scene, seconds: 0.8)
        let apply = CGPoint(x: settingsOrigin.x + scene.settings!.size.width - 38, y: settingsOrigin.y + scene.settings!.size.height - 23)
        try await move(&scene, to: apply)
        store.isApplying = true
        scene.settings = try await settingsImage()
        try add(scene, seconds: 0.5)
        store.isApplying = false
        applied = store.modes
        scene.modes = applied
        try add(scene, seconds: 0.5)

        scene.settings = nil
        for step in [0.35, 0.7, 1.0] {
            scene.tucked = step
            try add(scene, seconds: step < 1 ? 0.09 : 1.1)
        }
        let paravent = itemRect(for: .paravent, in: scene)
        try await move(&scene, to: CGPoint(x: paravent.midX, y: paravent.midY + 2))
        scene.panel = try await panelImage(highlighted: nil)
        try add(scene, seconds: 1.4)
        let panelOrigin = panelOrigin(scene.panel!, under: paravent)
        let index = store.panelItems.firstIndex { $0.id == clipboard }!
        let target = CGPoint(x: panelOrigin.x + 8 + 23 + CGFloat(index) * 48, y: panelOrigin.y + 8 + 21)
        try await move(&scene, to: target)
        scene.panel = try await panelImage(highlighted: clipboard)
        try add(scene, seconds: 0.9)

        scene.panel = nil
        scene.tucked = 0
        scene.pressed = clipboard
        scene.menuUnder = clipboard
        try add(scene, seconds: 2.4)

        scene.pressed = nil
        scene.menuUnder = nil
        scene.tucked = 1
        try add(scene, seconds: 0.4)
        try await move(&scene, to: CGPoint(x: target.x - 60, y: 320))
        try add(scene, seconds: 1.4)
    }

    private func move(_ scene: inout Scene, to target: CGPoint) async throws {
        let start = scene.pointer ?? target
        let steps = 6
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let eased = t * t * (3 - 2 * t)
            scene.pointer = CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
            try add(scene, seconds: 0.04)
        }
    }

    private func add(_ scene: Scene, seconds: Double) throws {
        guard let folder else { throw CaptureError("No output folder") }
        let image = render(scene)
        let name = String(format: "frame-%03d.png", frames.count)
        guard let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil) else {
            throw CaptureError("Could not write \(name)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError("Could not write \(name)") }
        frames.append((name, seconds))
    }

    private func finish() throws {
        guard let folder, let last = frames.last else { throw CaptureError("No frames") }
        // The concat demuxer drops the last duration unless the last file is listed once more.
        let list = frames.map { "file '\($0.name)'\nduration \($0.seconds)\n" }.joined() + "file '\(last.name)'\n"
        try list.write(to: folder.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Previews

    static func capturePreviews(to output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let stage = DemoStage(dark: name == "dark")
            try write(await stage.panelImage(highlighted: nil), to: output.appendingPathComponent("\(name)-panel.png"))
            try write(await stage.settingsImage(), to: output.appendingPathComponent("\(name)-settings.png"))
            stage.selection.tab = .general
            try write(await stage.settingsImage(), to: output.appendingPathComponent("\(name)-settings-general.png"))
            stage.updater.release = Release(tag: "v0.2.0", page: URL(string: "https://github.com/mehambas/paravent/releases/tag/v0.2.0")!, assets: [:])
            try write(await stage.settingsImage(), to: output.appendingPathComponent("\(name)-settings-update.png"))
            try write(await stage.panelImage(highlighted: nil), to: output.appendingPathComponent("\(name)-panel-update.png"))
            stage.store.showSamples([], images: [:], modes: [:])
            try write(await stage.panelImage(highlighted: nil), to: output.appendingPathComponent("\(name)-panel-empty.png"))
        }
        print("Previews: \(output.path)")
    }

    private static func write(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw CaptureError("Could not encode \(url.lastPathComponent)")
        }
        try png.write(to: url)
    }

    // MARK: Snapshots of the real views

    private func settingsImage() async throws -> NSImage {
        let window = OffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Paravent Settings")
        window.contentView = NSHostingView(rootView: SettingsView(store: store, updater: updater, selection: selection, onApply: {}))
        return try await snapshot(window, view: window.contentView?.superview)
    }

    private func panelImage(highlighted: String?) async throws -> NSImage {
        let view = NSHostingView(rootView: PanelView(store: store, updater: updater, onPress: { _ in }, onSettings: {}, onUpdate: {},
                                                     highlighted: highlighted))
        let window = OffscreenWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        return try await snapshot(window, view: view)
    }

    private func snapshot(_ window: NSWindow, view: NSView?) async throws -> NSImage {
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(350))
        guard let view else { throw CaptureError("No view to capture") }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CaptureError("No bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    // MARK: Drawing

    private struct Scene {
        var modes: [String: ItemMode]
        /// 0 while every icon shows, 1 once the divider has tucked the left ones away.
        var tucked: CGFloat = 0
        var settings: NSImage?
        var panel: NSImage?
        var pressed: String?
        var menuUnder: String?
        var pointer: CGPoint?
    }

    private enum Slot: Equatable {
        case sample(String), divider, paravent, system(Int)
    }

    private var ink: NSColor { dark ? .white : .black }

    /// Right to left from the clock: system icons, the visible samples, Paravent, the divider, the tucked samples.
    private func layout(_ scene: Scene) -> [(slot: Slot, rect: CGRect)] {
        var x = Self.canvas.width - 12 - clockWidth - 8
        var result: [(Slot, CGRect)] = []
        func place(_ slot: Slot, width: CGFloat) {
            x -= width
            result.append((slot, CGRect(x: x, y: 0, width: width, height: Self.barHeight)))
        }
        for index in Self.systemSymbols.indices.reversed() { place(.system(index), width: Self.slot) }
        for sample in Self.samples.reversed() where scene.modes[sample.id] == .visible { place(.sample(sample.id), width: Self.slot) }
        place(.paravent, width: Self.slot)
        place(.divider, width: Self.dividerSlot)
        for sample in Self.samples.reversed() where scene.modes[sample.id] != .visible { place(.sample(sample.id), width: Self.slot) }
        return result
    }

    private func itemRect(for slot: Slot, in scene: Scene) -> CGRect {
        layout(scene).first { $0.slot == slot }?.rect ?? .zero
    }

    private var clockWidth: CGFloat { clock.size().width }
    private var clock: NSAttributedString {
        NSAttributedString(string: "Fri Oct 16  9:41 AM", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink])
    }

    private func settingsOrigin(_ image: NSImage) -> CGPoint {
        CGPoint(x: (Self.canvas.width - image.size.width) / 2 - 90, y: Self.barHeight + 34)
    }

    private func panelOrigin(_ image: NSImage, under anchor: CGRect) -> CGPoint {
        CGPoint(x: min(anchor.midX - image.size.width / 2, Self.canvas.width - image.size.width - 8), y: anchor.maxY + 6)
    }

    private func render(_ scene: Scene) -> CGImage {
        let width = Int(Self.canvas.width * Self.scale), height = Int(Self.canvas.height * Self.scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: Self.scale, y: -Self.scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let colors = dark ? [NSColor(srgbRed: 0.11, green: 0.16, blue: 0.31, alpha: 1), NSColor(srgbRed: 0.29, green: 0.17, blue: 0.37, alpha: 1)]
                          : [NSColor(srgbRed: 0.80, green: 0.87, blue: 0.97, alpha: 1), NSColor(srgbRed: 0.96, green: 0.85, blue: 0.90, alpha: 1)]
        NSGradient(colors: colors)!.draw(in: NSRect(origin: .zero, size: Self.canvas), angle: -30)

        (dark ? NSColor.black.withAlphaComponent(0.32) : NSColor.white.withAlphaComponent(0.55)).setFill()
        NSRect(x: 0, y: 0, width: Self.canvas.width, height: Self.barHeight).fill()

        var x: CGFloat = 18
        for (index, title) in ["\u{F8FF}", "Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
            let font = index == 1 ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: index == 0 ? 15 : 13)
            let text = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: ink])
            text.draw(at: CGPoint(x: x, y: (Self.barHeight - text.size().height) / 2))
            x += text.size().width + (index == 0 ? 18 : 20)
        }
        clock.draw(at: CGPoint(x: Self.canvas.width - 12 - clockWidth, y: (Self.barHeight - clock.size().height) / 2))

        let dividerX = itemRect(for: .divider, in: scene).maxX
        for (slot, rect) in layout(scene) {
            var alpha: CGFloat = 1
            if rect.maxX <= dividerX { alpha = 1 - scene.tucked }
            if case .divider = slot, scene.tucked > 0 { alpha = 0 }
            guard alpha > 0.01 else { continue }
            if case .sample(let id) = slot, id == scene.pressed {
                (dark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.12)).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 2), xRadius: 6, yRadius: 6).fill()
            }
            let image: NSImage?
            switch slot {
            case .sample(let id): image = Self.glyph(Self.samples.first { $0.id == id }!.symbol, color: ink, size: 13)
            case .system(let index): image = Self.glyph(Self.systemSymbols[index], color: ink, size: 13)
            case .paravent: image = Self.tinted(NSImage(named: "MenuBarIconTemplate") ?? Self.glyph("rectangle.split.3x1", color: ink, size: 13), ink)
            case .divider: image = Self.tinted(NSImage(named: "MenuBarDividerTemplate") ?? Self.glyph("chevron.compact.left", color: ink, size: 13), ink)
            }
            if let image {
                let target = CGRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2, width: image.size.width, height: image.size.height)
                image.draw(in: target.integral, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            }
        }

        if let settings = scene.settings {
            let origin = settingsOrigin(settings)
            drawWindow(settings, in: CGRect(origin: origin, size: settings.size), radius: 12, context: context)
        }
        if let panel = scene.panel {
            let anchor = itemRect(for: .paravent, in: scene)
            let frame = CGRect(origin: panelOrigin(panel, under: anchor), size: panel.size)
            NSGraphicsContext.saveGraphicsState()
            context.setShadow(offset: CGSize(width: 0, height: 8), blur: 22, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            NSColor(white: 0.16, alpha: 0.94).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()
            panel.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if let id = scene.menuUnder {
            drawMenu(under: itemRect(for: .sample(id), in: scene), title: Self.samples.first { $0.id == id }!.name, context: context)
        }
        if let pointer = scene.pointer { drawPointer(at: pointer, context: context) }
        context.flush()
        return context.makeImage()!
    }

    /// NSCursor.arrow would bring along this Mac's pointer colors.
    private func drawPointer(at tip: CGPoint, context: CGContext) {
        let arrow = NSBezierPath()
        arrow.move(to: tip)
        for (x, y) in [(0, 16.5), (4, 12.7), (6.6, 18.6), (8.7, 17.7), (6.2, 12), (11.6, 12)] {
            arrow.line(to: CGPoint(x: tip.x + x, y: tip.y + y))
        }
        arrow.close()
        arrow.lineJoinStyle = .round
        NSGraphicsContext.saveGraphicsState()
        context.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor.white.setFill()
        arrow.lineWidth = 2.4
        NSColor.white.setStroke()
        arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.setFill()
        arrow.fill()
    }

    private func drawWindow(_ image: NSImage, in frame: CGRect, radius: CGFloat, context: CGContext) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        context.setShadow(offset: CGSize(width: 0, height: 14), blur: 40, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        (dark ? NSColor(white: 0.17, alpha: 1) : .white).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.12)).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    /// A stand-in for the menu of the clicked app.
    private func drawMenu(under anchor: CGRect, title: String, context: CGContext) {
        let rows: [String?] = ["Open \(title)", "Pause for 1 Hour", nil, "Settings…", "Quit \(title)"]
        let font = NSFont.menuFont(ofSize: 13)
        let width: CGFloat = 210
        let height = rows.reduce(CGFloat(10)) { $0 + ($1 == nil ? 11 : 22) }
        let frame = CGRect(x: anchor.minX - 6, y: Self.barHeight + 3, width: width, height: height)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState()
        context.setShadow(offset: CGSize(width: 0, height: 8), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        (dark ? NSColor(white: 0.19, alpha: 0.97) : NSColor(white: 0.97, alpha: 0.97)).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        var y = frame.minY + 5
        for row in rows {
            guard let row else {
                (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.1)).setFill()
                NSRect(x: frame.minX + 12, y: y + 5, width: width - 24, height: 1).fill()
                y += 11
                continue
            }
            NSAttributedString(string: row, attributes: [.font: font, .foregroundColor: ink]).draw(at: CGPoint(x: frame.minX + 14, y: y + 3))
            y += 22
        }
    }

    private static func glyph(_ symbol: String, color: NSColor, size: CGFloat) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) ?? NSImage()
        return tinted(image, color)
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

private final class OffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
