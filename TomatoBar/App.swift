import SwiftUI
import LaunchAtLogin

extension NSImage.Name {
    static let idle = Self("BarIconIdle")
    static let work = Self("BarIconWork")
    static let shortRest = Self("BarIconShortRest")
    static let longRest = Self("BarIconLongRest")
}

/* Menu bar font size, medium weight like the system clock */
private let digitFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
                                                        weight: .medium)

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
    private var popoverReposition: DispatchWorkItem?
    /* Status item center the popover is pointing at and popover frame, in screen coordinates */
    private var popoverAnchorX: CGFloat?
    private var popoverFrame: NSRect?
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

        /*
         Timer title changes the status item width and moves its window,
         keep the open popover pointing at the button
         */
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            /* Any window, the status item window may be replaced (e.g. on display changes) */
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(statusBarWindowDidChange(_:)),
                name: name,
                object: nil
            )
        }
    }

    @objc private func statusBarWindowDidChange(_ notification: Notification) {
        guard popover.isShown, let button = statusBarItem?.button,
              notification.object as? NSWindow === button.window
        else {
            return
        }
        /*
         AppKit follows the resize right away to an intermediate position,
         put the popover back before it's drawn there
         */
        if let frame = popoverFrame, let popoverWindow = popover.contentViewController?.view.window,
           popoverWindow.frame != frame
        {
            popoverWindow.setFrame(frame, display: true)
        }
        /*
         The window is resized first and moved afterwards, repositioning
         in between makes the popover jump back and forth. Wait for both.
         */
        popoverReposition?.cancel()
        let reposition = DispatchWorkItem { [weak self] in self?.repositionPopover() }
        popoverReposition = reposition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: reposition)
    }

    private func repositionPopover() {
        guard popover.isShown, let anchorX = popoverAnchorX, var frame = popoverFrame,
              let newAnchorX = statusBarItem?.button?.window?.frame.midX,
              let popoverWindow = popover.contentViewController?.view.window,
              newAnchorX != anchorX
        else {
            return
        }
        /* Center on the status item, but keep on screen like AppKit does */
        frame.origin.x = newAnchorX - frame.width / 2
        if let visible = popoverWindow.screen?.visibleFrame {
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        }
        popoverAnchorX = newAnchorX
        popoverFrame = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            popoverWindow.animator().setFrame(frame, display: true)
        }
    }

    func setTitle(title: String?) {
        let attributedTitle = NSAttributedString(
            string: title != nil ? " \(title!)" : "",
            attributes: [
                NSAttributedString.Key.font: digitFont,
                /* Digits have no descenders, lower them to center with the icon */
                NSAttributedString.Key.baselineOffset: -0.5,
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
            popoverAnchorX = button.window?.frame.midX
            popoverFrame = popover.contentViewController?.view.window?.frame
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
