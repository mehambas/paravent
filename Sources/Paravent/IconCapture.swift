import AppKit
import ScreenCaptureKit

enum IconCapture {
    static func capture(_ items: [BarItem]) async -> [String: CGImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return [:] }
        let windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: CGImage] = [:]

        await withTaskGroup(of: (String, CGImage?).self) { group in
            for item in items {
                guard let window = windows[item.windowID] else { continue }
                group.addTask {
                    let config = SCStreamConfiguration()
                    config.width = Int(item.frame.width) * 2
                    config.height = Int(item.frame.height) * 2
                    config.showsCursor = false
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    do {
                        let image: CGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        return (item.id, trimmed(image))
                    } catch {
                        return (item.id, nil)
                    }
                }
            }
            for await (id, image) in group {
                if let image { result[id] = image }
            }
        }
        return result
    }

    // Windows that are off-screen come back fully transparent; those are dropped so a cached image survives.
    private static func trimmed(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 12 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pad = 2
        let rect = CGRect(
            x: max(0, minX - pad), y: max(0, minY - pad),
            width: min(width, maxX + pad + 1) - max(0, minX - pad),
            height: min(height, maxY + pad + 1) - max(0, minY - pad)
        )
        return image.cropping(to: rect)
    }
}
