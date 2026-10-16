import ParaventCore
import ServiceManagement
import SwiftUI

struct ItemIcon: View {
    let image: NSImage?
    let fallback: NSImage?
    var height: CGFloat = 20

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let fallback {
                Image(nsImage: fallback).resizable().scaledToFit()
            } else {
                Image(systemName: "questionmark.square.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(height: height)
    }
}

struct PanelView: View {
    @ObservedObject var store: Store
    @ObservedObject var updater: Updater
    let onPress: (BarItem) -> Void
    let onSettings: () -> Void
    let onUpdate: () -> Void
    var highlighted: String?

    private let perRow = 7

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            content
            HStack(spacing: 0) {
                if let version = updater.release?.version {
                    Button(action: onUpdate) {
                        Label("Update to \(version.description)", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        let items = store.panelItems
        if items.isEmpty {
            Button("Choose icons in Settings…", action: onSettings)
                .buttonStyle(.plain)
                .padding(10)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(stride(from: 0, to: items.count, by: perRow)), id: \.self) { start in
                    HStack(spacing: 2) {
                        ForEach(items[start..<min(start + perRow, items.count)]) { item in
                            PanelButton(item: item, image: store.images[item.id], highlighted: highlighted == item.id) { onPress(item) }
                        }
                    }
                }
            }
        }
    }
}

private struct PanelButton: View {
    let item: BarItem
    let image: NSImage?
    var highlighted = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        ItemIcon(image: image, fallback: item.appIcon, height: 26)
            .frame(minWidth: 26)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(hovering || highlighted ? Color.white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .help(item.name)
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(.isButton)
    }
}

enum SettingsTab: Hashable {
    case menuBar, general
}

final class SettingsSelection: ObservableObject {
    @Published var tab = SettingsTab.menuBar
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var updater: Updater
    @ObservedObject var selection: SettingsSelection
    let onApply: () -> Void

    var body: some View {
        TabView(selection: $selection.tab) {
            MenuBarSettings(store: store, onApply: onApply)
                .tabItem { Text("Menu Bar") }
                .tag(SettingsTab.menuBar)
            GeneralSettings(updater: updater)
                .tabItem { Text("General") }
                .tag(SettingsTab.general)
        }
        .padding(.top, 8)
        .frame(minWidth: 600, minHeight: 460)
    }
}

private struct MenuBarSettings: View {
    @ObservedObject var store: Store
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !store.permissionsGranted {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Paravent needs Accessibility and Screen Recording permission.")
                    Spacer()
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                    }
                }
                .padding(12)
                .background(.yellow.opacity(0.12))
            }
            Text("**In Panel** tucks an icon behind the divider and shows it when you point at Paravent’s icon. **Hidden** tucks it away completely.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            List(store.items) { item in
                HStack(spacing: 12) {
                    ItemIcon(image: store.images[item.id], fallback: item.appIcon, height: 24)
                        .frame(width: 80, height: 40)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                    Text(item.name)
                    Spacer()
                    Picker(item.name, selection: Binding(
                        get: { store.mode(of: item) },
                        set: { store.setMode($0, for: item) }
                    )) {
                        ForEach(ItemMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    .disabled(item.isPinned)
                }
                .padding(.vertical, 2)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if store.isApplying {
                            Text("Moving icons… Don’t touch the mouse.")
                        } else {
                            Text("Apply moves the icons by ⌘-dragging them. The pointer moves on its own for a few seconds.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    ForEach(store.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }
                Spacer()
                Button("Apply", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isApplying)
            }
            .padding(12)
        }
    }
}

private struct GeneralSettings: View {
    @ObservedObject var updater: Updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            loginError = String(localized: "Couldn’t change Open at login: \(error.localizedDescription)")
                        }
                    }
                if let loginError { WarningLine(text: loginError) }
            }
            Section {
                Toggle(isOn: $updater.automatic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for updates automatically")
                        detail(Text("Once a day Paravent asks GitHub for the latest version number."))
                    }
                }
                .toggleStyle(.switch)
                UpdateRow(updater: updater)
            } header: {
                Text("Updates")
            } footer: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Everything stays on this Mac.").foregroundStyle(.primary)
                        detail(Text("No telemetry. The update check sends nothing about you or your Mac."))
                    }
                } icon: {
                    Image(systemName: "lock").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateRow: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if let release = updater.release, let version = release.version {
            LabeledContent {
                Button("Download and Install") { updater.install() }
                    .disabled(busy)
                    .help("Downloads the disk image and opens it, then Paravent quits so you can drag the new version to Applications.")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paravent \(version.description) is available")
                    switch updater.status {
                    case .downloading(let fraction):
                        ProgressView(value: fraction).accessibilityLabel(Text("Downloading Paravent \(version.description)"))
                    case .opening:
                        detail(Text("Drag Paravent from the disk image to Applications and replace this version."))
                    case .failed(let reason):
                        WarningLine(text: reason)
                    default:
                        HStack(spacing: 4) {
                            detail(Text("You have \(updater.current.description)."))
                            Link("Release Notes", destination: release.page).font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            LabeledContent {
                Button("Check Now") { updater.check(manual: true) }.disabled(updater.status == .checking)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paravent \(updater.current.description)")
                    switch updater.status {
                    case .checking: detail(Text("Checking for updates…"))
                    case .upToDate: detail(Text("This is the latest version."))
                    case .checkFailed(let reason): WarningLine(text: String(localized: "Couldn’t check for updates. \(reason)"))
                    default:
                        if let last = updater.lastCheck {
                            detail(Text("Last checked: \(last.formatted(date: .abbreviated, time: .shortened))"))
                        } else {
                            detail(Text("Not checked yet."))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var busy: Bool {
        switch updater.status {
        case .downloading, .opening: return true
        default: return false
        }
    }
}

private struct WarningLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.caption)
    }
}

private func detail(_ text: Text) -> some View {
    text.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
}
