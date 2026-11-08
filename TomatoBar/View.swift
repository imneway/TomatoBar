import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

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

/* Work intervals of the current set: done, in progress, to go */
private struct SetProgressView: View {
    @ObservedObject var timer: TBTimer

    var body: some View {
        let total = max(timer.workIntervalsInSet, 1)
        let done = min(timer.consecutiveWorkIntervals, total)
        HStack(spacing: 6) {
            ForEach(0 ..< total, id: \.self) { index in
                if index < done {
                    Circle().fill(Color.accentColor)
                } else if index == done, timer.state == .work {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                }
            }
            .frame(width: 7, height: 7)
        }
        .frame(maxWidth: .infinity)
        .help(String.localizedStringWithFormat(
            NSLocalizedString("TBPopoverView.setProgress.help", comment: "Set progress hint"),
            done, total
        ))
    }
}

struct TBPopoverView: View {
    @ObservedObject var timer: TBTimer
    @State private var buttonHovered = false
    @State private var lastMainButtonClick = Date.distantPast

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

            SetProgressView(timer: timer)

            Group {
                Button {
                    TBStatusItem.shared.showSettings()
                } label: {
                    Text(NSLocalizedString("TBPopoverView.settings.label",
                                           comment: "Settings label"))
                    Spacer()
                    Text("⌘ ,").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",")
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
            .padding(12)
    }
}

#if DEBUG
    func debugSize(proxy: GeometryProxy) -> some View {
        print("Optimal popover size:", proxy.size)
        return Color.clear
    }
#endif
