import AppKit

@MainActor
final class Arranger {
    private enum Step {
        case moveDivider(before: BarItem?, after: BarItem?)
        case moveItem(BarItem, leftOfDivider: Bool)
    }

    private let store: Store
    private let divider: DividerController

    init(store: Store, divider: DividerController) {
        self.store = store
        self.divider = divider
    }

    func apply() async {
        guard !store.isApplying else { return }
        store.isApplying = true
        defer { store.isApplying = false }
        store.notes = []

        let rowTop = MenuBarScanner.rowTop(for: NSEvent.mouseLocation)
        divider.reveal()
        try? await Task.sleep(for: .milliseconds(700))

        var attempts: [String: Int] = [:]
        for _ in 0..<80 {
            let items = await Task.detached { MenuBarScanner.scan(preferredRowTop: rowTop) }.value
            guard let boundary = divider.liveWindow(rowTop: rowTop), boundary.frame.width < 100,
                  let step = nextStep(items: items, dividerFrame: boundary.frame, attempts: &attempts) else { break }
            await perform(step, boundary: boundary)
            try? await Task.sleep(for: .milliseconds(500))
        }

        await store.refresh()
        let finalItems = await Task.detached { MenuBarScanner.scan(preferredRowTop: rowTop) }.value
        if let boundary = divider.liveWindow(rowTop: rowTop), boundary.frame.width < 100 {
            store.notes = Array(Set(finalItems.filter {
                !$0.isPinned && (store.mode(of: $0) != .visible) != ($0.frame.midX < boundary.frame.midX)
            }.map { String(localized: "Couldn’t move \($0.name)") })).sorted()
        } else {
            store.notes = [String(localized: "The menu bar changed. Try Apply again.")]
        }
        divider.collapse()
        Log.write("apply done, notes: \(store.notes)")
    }

    func activate(_ item: BarItem) async {
        let hidden = divider.collapsed && store.mode(of: item) != .visible
        guard hidden else {
            ItemPress.press(item)
            return
        }
        // The item's menu opens where the item sits, so it has to be back in the bar while the menu is open.
        let started = Date()
        divider.reveal()
        // Pressing before macOS has moved the item back would open the menu at its off-screen spot.
        var target = item
        if item.axElement != nil {
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(40))
                if let p = ItemPress.position(of: item), p.x > 0 { break }
            }
        } else {
            try? await Task.sleep(for: .milliseconds(400))
            let rowTop = MenuBarScanner.rowTop(for: NSEvent.mouseLocation)
            target = await Task.detached { MenuBarScanner.scan(preferredRowTop: rowTop) }.value.first { $0.id == item.id } ?? item
        }
        ItemPress.press(target)
        Log.write("activate \(item.name): press after \(Int(Date().timeIntervalSince(started) * 1000)) ms")

        try? await Task.sleep(for: .milliseconds(1200))
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline, Self.hasOpenMenu(pid: item.pid) {
            try? await Task.sleep(for: .milliseconds(300))
        }
        divider.collapse()
    }

    private static func hasOpenMenu(pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { w in
            guard w[kCGWindowOwnerPID as String] as? pid_t == pid,
                  (w[kCGWindowLayer as String] as? Int ?? 0) >= 25,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dict) else { return false }
            return frame.height > 50
        }
    }

    func reveal() { divider.reveal() }
    func collapse() { divider.collapse() }

    private func reachable(_ items: [BarItem]) -> [BarItem] {
        return items
            // The scanner already limits this list to the active menu-bar row. Keep items
            // on either side of the divider eligible so a misplaced icon can be moved back.
            .filter { !$0.isPinned }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private func nextStep(items: [BarItem], dividerFrame: CGRect, attempts: inout [String: Int]) -> Step? {
        let movable = reachable(items)
        let dividerMid = dividerFrame.midX
        func isLeft(_ item: BarItem) -> Bool { item.frame.midX < dividerMid }
        func wantsHidden(_ item: BarItem) -> Bool { store.mode(of: item) != .visible }

        func cost(split: Int) -> Int {
            movable.enumerated().filter { index, item in
                index < split ? !wantsHidden(item) : wantsHidden(item)
            }.count
        }
        let current = movable.filter(isLeft).count
        let best = (0...movable.count).min { a, b in
            let ca = cost(split: a), cb = cost(split: b)
            return ca != cb ? ca < cb : abs(a - current) < abs(b - current)
        } ?? current

        if cost(split: best) < cost(split: current), attempts["divider", default: 0] < 3 {
            attempts["divider", default: 0] += 1
            return .moveDivider(
                before: best < movable.count ? movable[best] : nil,
                after: best > 0 ? movable[best - 1] : nil
            )
        }

        for item in movable where wantsHidden(item) != isLeft(item) {
            let key = "\(item.id)/\(wantsHidden(item))"
            if attempts[key, default: 0] >= 2 {
                continue
            }
            attempts[key, default: 0] += 1
            return .moveItem(item, leftOfDivider: wantsHidden(item))
        }
        return nil
    }

    private func perform(_ step: Step, boundary: MenuBarWindow) async {
        let d = boundary.frame
        switch step {
        case let .moveDivider(before, after):
            let targetX = before.map { $0.frame.minX - 1 } ?? (after.map { $0.frame.maxX + 1 } ?? d.minX)
            Log.write("drag divider window=\(boundary.id) to x=\(targetX)")
            await ItemMover.drag(windowID: boundary.id, to: CGPoint(x: targetX, y: d.midY))
        case let .moveItem(item, leftOfDivider):
            let targetX = leftOfDivider ? d.minX - 1 : d.maxX + 1
            Log.write("drag \(item.name) id=\(item.id) window=\(item.windowID) from=\(item.frame) to x=\(targetX)")
            await ItemMover.drag(windowID: item.windowID, to: CGPoint(x: targetX, y: d.midY))
        }
    }
}
