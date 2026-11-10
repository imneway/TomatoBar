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

struct TBPopoverView: View {
    @ObservedObject var timer: TBTimer
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
            return stopLabel
        case .workDone:
            return startRestLabel
        case .restDone:
            return startWorkLabel
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            /* Overtime shrinks to fit */
            Text(timer.state == .idle ? timer.workIntervalString : timer.timeLeftString)
                .font(.system(size: 54, weight: .medium).monospacedDigit())
                .foregroundColor(timer.state == .idle ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)

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
                } label: {
                    Text(mainButtonLabel)
                        .frame(maxWidth: .infinity)
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
