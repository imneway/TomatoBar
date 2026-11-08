import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

private struct IntervalsView: View {
    @EnvironmentObject var timer: TBTimer
    private var minStr = NSLocalizedString("IntervalsView.min", comment: "min")
    private var offStr = NSLocalizedString("IntervalsView.reminderInterval.off", comment: "Off")

    var body: some View {
        VStack(spacing: 10) {
            Stepper(value: $timer.workIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.workIntervalLength.label",
                                           comment: "Work interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.workIntervalLength))
                }
            }
            Stepper(value: $timer.shortRestIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.shortRestIntervalLength.label",
                                           comment: "Short rest interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.shortRestIntervalLength))
                }
            }
            Stepper(value: $timer.longRestIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.longRestIntervalLength.label",
                                           comment: "Long rest interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.longRestIntervalLength))
                }
            }
            .help(NSLocalizedString("IntervalsView.longRestIntervalLength.help",
                                    comment: "Long rest interval hint"))
            Stepper(value: $timer.workIntervalsInSet, in: 1 ... 10) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.workIntervalsInSet.label",
                                           comment: "Work intervals in a set label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(timer.workIntervalsInSet)")
                }
            }
            .help(NSLocalizedString("IntervalsView.workIntervalsInSet.help",
                                    comment: "Work intervals in set hint"))
            Stepper(value: $timer.reminderInterval, in: 0 ... 30) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.reminderInterval.label",
                                           comment: "Reminder interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(timer.reminderInterval > 0 ?
                        String.localizedStringWithFormat(minStr, timer.reminderInterval) :
                        offStr)
                }
            }
            .help(NSLocalizedString("IntervalsView.reminderInterval.help",
                                    comment: "Reminder interval hint"))
            .disabled(!timer.manualNextPhase)
        }
    }
}

private struct GeneralView: View {
    @EnvironmentObject var timer: TBTimer
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KeyboardShortcuts.Recorder(for: .startStopTimer) {
                Text(NSLocalizedString("SettingsView.shortcut.label",
                                       comment: "Shortcut label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle(isOn: $timer.manualNextPhase) {
                Text(NSLocalizedString("SettingsView.manualNextPhase.label",
                                       comment: "Start next interval manually label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.mini)
            Toggle(isOn: $timer.showTimerInMenuBar) {
                Text(NSLocalizedString("SettingsView.showTimerInMenuBar.label",
                                       comment: "Show timer in menu bar label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.mini)
                .onChange(of: timer.showTimerInMenuBar) { _ in
                    timer.updateTimeLeft()
                }
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text(NSLocalizedString("SettingsView.launchAtLogin.label",
                                       comment: "Launch at login label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.mini)
            Button(NSLocalizedString("SettingsWindow.about.label", comment: "About label")) {
                NSApp.orderFrontStandardAboutPanel()
            }
            .buttonStyle(.link)
            .padding(.top, 6)
        }
    }
}

private struct VolumeSlider: View {
    @Binding var volume: Double

    var body: some View {
        Slider(value: $volume, in: 0...2) {
            Text(String(format: "%.1f", volume))
        }.gesture(TapGesture(count: 2).onEnded({
            volume = 1.0
        }))
    }
}

private struct SoundsView: View {
    @EnvironmentObject var player: TBPlayer

    private func row(_ label: String, volume: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(maxWidth: .infinity, alignment: .leading)
            VolumeSlider(volume: volume).frame(width: 180)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            row(NSLocalizedString("SoundsView.isWindupEnabled.label", comment: "Windup label"),
                volume: $player.windupVolume)
            row(NSLocalizedString("SoundsView.isDingEnabled.label", comment: "Ding label"),
                volume: $player.dingVolume)
            row(NSLocalizedString("SoundsView.isTickingEnabled.label", comment: "Ticking label"),
                volume: $player.tickingVolume)
        }
    }
}

/*
 Pull-down "+" button listing the running apps, with the open panel as the last resort.
 AppKit menu is rebuilt every time it opens, so newly launched apps show up.
 */
private struct AddAppButton: NSViewRepresentable {
    @ObservedObject var watcher: TBAppWatcher

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.controlSize = .small
        button.imagePosition = .imageOnly
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        /* The first item is the pull-down button's label */
        button.menu?.addItem(NSMenuItem())
        button.menu?.items.first?.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        button.menu?.delegate = context.coordinator
        button.toolTip = NSLocalizedString("AppsView.add.help", comment: "Add app hint")
        return button
    }

    func updateNSView(_: NSPopUpButton, context: Context) {
        context.coordinator.watcher = watcher
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(watcher: watcher)
    }

    class Coordinator: NSObject, NSMenuDelegate {
        var watcher: TBAppWatcher

        init(watcher: TBAppWatcher) {
            self.watcher = watcher
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            let label = menu.items.first
            menu.removeAllItems()
            if let label = label {
                menu.addItem(label)
            }
            for app in watcher.runningAppsToAdd {
                let item = NSMenuItem(title: app.localizedName ?? app.bundleIdentifier ?? "",
                                      action: #selector(addRunningApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app.bundleURL
                let icon = app.icon
                icon?.size = NSSize(width: 16, height: 16)
                item.image = icon
                menu.addItem(item)
            }
            if menu.items.count > 1 {
                menu.addItem(.separator())
            }
            let choose = NSMenuItem(title: NSLocalizedString("AppsView.add.choose", comment: "Choose app item"),
                                    action: #selector(chooseApp), keyEquivalent: "")
            choose.target = self
            menu.addItem(choose)
        }

        @objc private func addRunningApp(_ sender: NSMenuItem) {
            if let url = sender.representedObject as? URL {
                watcher.add(url: url)
            }
        }

        @objc private func chooseApp() {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            panel.message = NSLocalizedString("AppsView.add.message", comment: "Open panel message")
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK {
                for url in panel.urls {
                    watcher.add(url: url)
                }
            }
        }
    }
}

private struct AppsView: View {
    @EnvironmentObject var timer: TBTimer
    @ObservedObject var watcher: TBAppWatcher
    @State private var selection: String?
    private var minStr = NSLocalizedString("IntervalsView.min", comment: "min")
    private var secStr = NSLocalizedString("AppsView.sec", comment: "sec")

    init(watcher: TBAppWatcher) {
        self.watcher = watcher
    }

    var body: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $timer.suggestStart) {
                Text(NSLocalizedString("AppsView.suggestStart.label",
                                       comment: "Suggest starting label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.mini)
                .help(NSLocalizedString("AppsView.suggestStart.help",
                                        comment: "Suggest starting hint"))
                .onChange(of: timer.suggestStart) { _ in
                    timer.updateAppWatcher()
                }
            Stepper(value: $timer.suggestStartAfter, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("AppsView.suggestStartAfter.label",
                                           comment: "Suggest after label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.suggestStartAfter))
                }
            }
            .help(NSLocalizedString("AppsView.suggestStartAfter.help", comment: "Suggest after hint"))
            .onChange(of: timer.suggestStartAfter) { _ in
                timer.updateAppWatcher()
            }
            Stepper(value: $timer.suggestStartGracePeriod, in: 0 ... 600, step: 30) {
                HStack {
                    Text(NSLocalizedString("AppsView.gracePeriod.label",
                                           comment: "Grace period label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(secStr, timer.suggestStartGracePeriod))
                }
            }
            .help(NSLocalizedString("AppsView.gracePeriod.help", comment: "Grace period hint"))
            .onChange(of: timer.suggestStartGracePeriod) { _ in
                timer.updateAppWatcher()
            }
            List(watcher.watchedApps, selection: $selection) { app in
                HStack(spacing: 4) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(app.displayName)
                        .lineLimit(1)
                }
                .frame(height: 16)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 160)
            HStack(spacing: 4) {
                AddAppButton(watcher: watcher).fixedSize()
                Button {
                    if let selection = selection {
                        watcher.remove(id: selection)
                        self.selection = nil
                    }
                } label: {
                    Image(systemName: "minus").frame(width: 12)
                }
                .disabled(selection == nil)
                .help(NSLocalizedString("AppsView.remove.help", comment: "Remove app hint"))
                Spacer()
            }
            .controlSize(.small)
            .padding(.top, -6)
        }
    }
}

private enum SettingsPage: String, CaseIterable {
    case general, intervals, sounds, apps

    var label: String {
        switch self {
        case .general:
            return NSLocalizedString("SettingsWindow.general.label", comment: "General tab")
        case .intervals:
            return NSLocalizedString("SettingsWindow.intervals.label", comment: "Intervals tab")
        case .sounds:
            return NSLocalizedString("SettingsWindow.sounds.label", comment: "Sounds tab")
        case .apps:
            return NSLocalizedString("SettingsWindow.apps.label", comment: "Apps tab")
        }
    }

    var symbol: String {
        switch self {
        case .general:
            return "gearshape"
        case .intervals:
            return "timer"
        case .sounds:
            return "speaker.wave.2"
        case .apps:
            return "app.badge"
        }
    }

    @ViewBuilder
    func view(timer: TBTimer) -> some View {
        switch self {
        case .general:
            GeneralView().environmentObject(timer)
        case .intervals:
            IntervalsView().environmentObject(timer)
        case .sounds:
            SoundsView().environmentObject(timer.player)
        case .apps:
            AppsView(watcher: timer.appWatcher).environmentObject(timer)
        }
    }
}

/* Each page keeps its own height, the window is resized to fit the selected one */
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        if let id = item?.identifier as? String {
            UserDefaults.standard.set(id, forKey: "settingsPage")
        }
        fitWindow(animate: view.window?.isVisible ?? false)
    }

    func fitWindow(animate: Bool) {
        guard let window = view.window,
              let size = tabView.selectedTabViewItem?.viewController?.view.fittingSize
        else {
            return
        }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        /* Keep the title bar in place */
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        window.setFrame(frame, display: true, animate: animate)
    }
}

private final class SettingsWindow: NSWindow {
    /*
     The app has no visible main menu, but its key equivalents still work:
     handle Close here, and keep ⌘, from opening the empty SwiftUI Settings scene
     */
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w":
                performClose(nil)
                return true
            case ",":
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class TBSettingsWindowController: NSWindowController {
    convenience init(timer: TBTimer) {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        for page in SettingsPage.allCases {
            let hostingView = NSHostingView(rootView: page.view(timer: timer)
                .frame(width: 360)
                .padding(20))
            let controller = NSViewController()
            controller.view = hostingView
            controller.title = page.label
            let item = NSTabViewItem(viewController: controller)
            item.identifier = page.rawValue
            item.label = page.label
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.label)
            tabs.addTabViewItem(item)
        }
        if let saved = UserDefaults.standard.string(forKey: "settingsPage"),
           let index = SettingsPage.allCases.firstIndex(where: { $0.rawValue == saved }) {
            tabs.selectedTabViewItemIndex = index
        }

        let window = SettingsWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        self.init(window: window)
        tabs.fitWindow(animate: false)
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
