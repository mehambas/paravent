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

        divider.reveal()
        try? await Task.sleep(for: .milliseconds(700))

        var attempts: [String: Int] = [:]
        for _ in 0..<80 {
            let rowTop = MenuBarScanner.rowTop(for: NSEvent.mouseLocation)
            let items = await Task.detached { MenuBarScanner.scan(preferredRowTop: rowTop) }.value
            guard let step = nextStep(items: items, attempts: &attempts) else { break }
            await perform(step, items: items)
            try? await Task.sleep(for: .milliseconds(500))
        }

        await store.refresh()
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

    private func nextStep(items: [BarItem], attempts: inout [String: Int]) -> Step? {
        let movable = reachable(items)
        let dividerMid = divider.frame.midX
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
                let note = String(localized: "Couldn’t move \(item.name)")
                if !store.notes.contains(note) { store.notes.append(note) }
                continue
            }
            attempts[key, default: 0] += 1
            return .moveItem(item, leftOfDivider: wantsHidden(item))
        }
        return nil
    }

    private func perform(_ step: Step, items: [BarItem]) async {
        let y = items.first?.frame.midY ?? 15
        let d = divider.frame
        switch step {
        case let .moveDivider(before, after):
            Log.write("divider frame \(d) window \(divider.windowID)")
            Log.write("divider -> before \(before?.name ?? "-") after \(after?.name ?? "-")")
            let targetX = before.map { $0.frame.minX } ?? (after.map { $0.frame.maxX } ?? d.minX)
            Log.write("drag divider from x=\(d.midX) to x=\(targetX), rowY=\(y)")
            await ItemMover.drag(from: CGPoint(x: d.midX, y: y), to: CGPoint(x: targetX, y: y))
        case let .moveItem(item, leftOfDivider):
            Log.write("move \(item.name) -> \(leftOfDivider ? "left" : "right") of divider")
            let targetX = leftOfDivider ? d.minX : d.maxX
            Log.write("drag \(item.name) from \(item.frame.midX),\(item.frame.midY) to \(targetX),\(y); divider=\(d)")
            await ItemMover.drag(from: CGPoint(x: item.frame.midX, y: item.frame.midY), to: CGPoint(x: targetX, y: y))
        }
    }
}
