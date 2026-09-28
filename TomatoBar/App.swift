import SwiftUI
import LaunchAtLogin

extension NSImage.Name {
    static let idle = Self("BarIconIdle")
    static let work = Self("BarIconWork")
    static let shortRest = Self("BarIconShortRest")
    static let longRest = Self("BarIconLongRest")
}

private let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(TBStatusItem.self) var appDelegate

    init() {
        TBStatusItem.shared = appDelegate
        LaunchAtLogin.migrateIfNeeded()
        logger.append(event: TBLogEventAppStart())
    }

    var body: some Scene {
        Settings {}
    }
}

class TBStatusItem: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var popover = NSPopover()
    private var popoverCloseEventTime: TimeInterval?
    private var statusBarItem: NSStatusItem?
    static var shared: TBStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        let view = TBPopoverView()

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSViewController()
        let hostingView = NSHostingView(rootView: view)
        let height = hostingView.intrinsicContentSize.height
        if #available(macOS 13.0, *) {
            /* Size is fixed here, don't let the hosting view resize the popover on every show */
            hostingView.sizingOptions = []
        }
        popover.contentViewController?.view = hostingView
        popover.contentSize = NSSize(width: 260, height: height)

        statusBarItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusBarItem?.button?.imagePosition = .imageLeft
        setIcon(name: .idle)
        statusBarItem?.button?.action = #selector(TBStatusItem.togglePopover(_:))
        /* Open on press like system menu bar items, not on release */
        statusBarItem?.button?.sendAction(on: [.leftMouseDown])
    }

    func setTitle(title: String?) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 0.9
        paragraphStyle.alignment = NSTextAlignment.center

        let attributedTitle = NSAttributedString(
            string: title != nil ? " \(title!)" : "",
            attributes: [
                NSAttributedString.Key.font: digitFont,
                NSAttributedString.Key.paragraphStyle: paragraphStyle
            ]
        )
        statusBarItem?.button?.attributedTitle = attributedTitle
    }

    func setIcon(name: NSImage.Name) {
        statusBarItem?.button?.image = NSImage(named: name)
    }

    func showPopover(_: AnyObject?) {
        if let button = statusBarItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }

    func popoverWillClose(_: Notification) {
        popoverCloseEventTime = NSApp.currentEvent?.timestamp
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
            return
        }
        /* Skip the click that has just closed the transient popover */
        if let closeTime = popoverCloseEventTime, NSApp.currentEvent?.timestamp == closeTime {
            return
        }
        showPopover(sender)
    }
}
