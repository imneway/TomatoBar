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
        VStack {
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
            Spacer().frame(minHeight: 0)
        }
        .controlSize(.small)
        .padding(4)
    }
}

private struct SettingsView: View {
    @EnvironmentObject var timer: TBTimer
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    var body: some View {
        VStack {
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
            Toggle(isOn: $timer.suggestStart) {
                Text(NSLocalizedString("SettingsView.suggestStart.label",
                                       comment: "Suggest starting label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.mini)
                .help(NSLocalizedString("SettingsView.suggestStart.help",
                                        comment: "Suggest starting hint"))
                .onChange(of: timer.suggestStart) { _ in
                    timer.updateAppWatcher()
                }
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text(NSLocalizedString("SettingsView.launchAtLogin.label",
                                       comment: "Launch at login label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.mini)
            Spacer().frame(minHeight: 0)
        }
        .controlSize(.small)
        .padding(4)
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

    private var columns = [
        GridItem(.flexible()),
        GridItem(.fixed(110))
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("SoundsView.isWindupEnabled.label",
                                   comment: "Windup label"))
            VolumeSlider(volume: $player.windupVolume)
            Text(NSLocalizedString("SoundsView.isDingEnabled.label",
                                   comment: "Ding label"))
            VolumeSlider(volume: $player.dingVolume)
            Text(NSLocalizedString("SoundsView.isTickingEnabled.label",
                                   comment: "Ticking label"))
            VolumeSlider(volume: $player.tickingVolume)
        }.padding(4)
        Spacer().frame(minHeight: 0)
    }
}

private enum ChildView: Int, CaseIterable {
    case intervals, settings, sounds

    var label: String {
        switch self {
        case .intervals:
            return NSLocalizedString("TBPopoverView.intervals.label", comment: "Intervals label")
        case .settings:
            return NSLocalizedString("TBPopoverView.settings.label", comment: "Settings label")
        case .sounds:
            return NSLocalizedString("TBPopoverView.sounds.label", comment: "Sounds label")
        }
    }
}

/*
 SwiftUI segmented picker is inset from the edges on macOS,
 use AppKit control to fill the width and align with the buttons.
 */
private struct ChildViewPicker: NSViewRepresentable {
    @Binding var selection: ChildView

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ChildView.allCases.map(\.label),
                                         trackingMode: .selectOne,
                                         target: context.coordinator,
                                         action: #selector(Coordinator.selectionChanged(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context _: Context) {
        control.selectedSegment = selection.rawValue
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    class Coordinator: NSObject {
        var selection: Binding<ChildView>

        init(selection: Binding<ChildView>) {
            self.selection = selection
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            selection.wrappedValue = ChildView(rawValue: sender.selectedSegment) ?? .intervals
        }
    }
}

/* Large buttons are capsules since macOS 26, keep the rounded rectangle */
private struct MainButtonSize: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 12.0, *) {
            content
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle)
        } else {
            content.controlSize(.large)
        }
    }
}

struct TBPopoverView: View {
    @ObservedObject var timer = TBTimer()
    @State private var buttonHovered = false
    @State private var lastMainButtonClick = Date.distantPast
    @State private var activeChildView = ChildView.intervals

    private var startLabel = NSLocalizedString("TBPopoverView.start.label", comment: "Start label")
    private var stopLabel = NSLocalizedString("TBPopoverView.stop.label", comment: "Stop label")
    private var startRestLabel = NSLocalizedString("TBPopoverView.startRest.label",
                                                   comment: "Start break label")
    private var startWorkLabel = NSLocalizedString("TBPopoverView.startWork.label",
                                                   comment: "Start work label")

    private var mainButtonLabel: String {
        switch timer.state {
        case .idle:
            return startLabel
        case .work, .rest:
            return buttonHovered ? stopLabel : timer.timeLeftString
        case .workDone:
            return "\(startRestLabel)  \(timer.timeLeftString)"
        case .restDone:
            return "\(startWorkLabel)  \(timer.timeLeftString)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    /* Popover stays open, so a double click would undo the first one */
                    guard Date().timeIntervalSince(lastMainButtonClick) > NSEvent.doubleClickInterval else {
                        return
                    }
                    lastMainButtonClick = Date()
                    if timer.isWaiting {
                        timer.startNext()
                    } else {
                        timer.startStop()
                    }
                    /*
                     Keep the popover open for the next click, but don't show
                     "Stop" under the cursor right after starting
                     */
                    buttonHovered = false
                } label: {
                    Text(mainButtonLabel)
                        .font(.system(.body).monospacedDigit())
                        .frame(maxWidth: .infinity)
                }
                .onHover { over in
                    buttonHovered = over
                }
                .keyboardShortcut(.defaultAction)

                /* Overtime can only be stopped from here, notifications have no stop action */
                if timer.isWaiting {
                    Button {
                        timer.startStop()
                    } label: {
                        Text(stopLabel)
                    }
                }
            }
            .modifier(MainButtonSize())

            ChildViewPicker(selection: $activeChildView)

            GroupBox {
                switch activeChildView {
                case .intervals:
                    IntervalsView().environmentObject(timer)
                case .settings:
                    SettingsView().environmentObject(timer)
                case .sounds:
                    SoundsView().environmentObject(timer.player)
                }
            }

            Group {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel()
                } label: {
                    Text(NSLocalizedString("TBPopoverView.about.label",
                                           comment: "About label"))
                    Spacer()
                    Text("⌘ A").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a")
                Button {
                    NSApplication.shared.terminate(self)
                } label: {
                    Text(NSLocalizedString("TBPopoverView.quit.label",
                                           comment: "Quit label"))
                    Spacer()
                    Text("⌘ Q").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
        }
        #if DEBUG
            /*
             After several hours of Googling and trying various StackOverflow
             recipes I still haven't figured a reliable way to auto resize
             popover to fit all it's contents (pull requests are welcome!).
             The following code block is used to determine the optimal
             geometry of the popover.
             */
            .overlay(
                GeometryReader { proxy in
                    debugSize(proxy: proxy)
                }
            )
        #endif
            /* Use values from GeometryReader */
//            .frame(width: 240, height: 276)
            .padding(12)
    }
}

#if DEBUG
    func debugSize(proxy: GeometryProxy) -> some View {
        print("Optimal popover size:", proxy.size)
        return Color.clear
    }
#endif
