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
    private var popoverAnchorSlide: Timer?
    /*
     Invisible window over the status item the popover is attached to.
     AppKit makes popovers attached to the status item button follow its
     resize immediately, which makes the popover and its arrow jump when
     the timer title appears or disappears. We move this one ourselves.
     */
    private lazy var popoverAnchor: NSWindow = {
        let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return window
    }()
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
        guard popover.isShown, notification.object as? NSWindow === statusBarItem?.button?.window else {
            return
        }
        /* The window is resized first and moved afterwards, wait for both */
        popoverReposition?.cancel()
        let reposition = DispatchWorkItem { [weak self] in self?.repositionPopover() }
        popoverReposition = reposition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: reposition)
    }

    /*
     Fixed size anchor at the center of the status item. It only slides and never
     changes width: AppKit follows its moves, but keeps its old size meanwhile.
     */
    private var popoverAnchorFrame: NSRect? {
        guard let button = statusBarItem?.button, let window = button.window else {
            return nil
        }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSRect(x: frame.midX - 10, y: frame.minY, width: 20, height: frame.height)
    }

    private func repositionPopover() {
        guard popover.isShown, let target = popoverAnchorFrame, target != popoverAnchor.frame
        else {
            return
        }
        slidePopoverAnchor(to: target)
    }

    /*
     AppKit keeps the popover attached to the anchor while it slides.
     Window animator doesn't animate a move without resize, so step it ourselves.
     */
    private func slidePopoverAnchor(to target: NSRect) {
        popoverAnchorSlide?.invalidate()
        let start = popoverAnchor.frame
        let startTime = Date()
        let duration = 0.2
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let progress = min(1, Date().timeIntervalSince(startTime) / duration)
            let eased = 1 - pow(1 - progress, 3)
            var frame = target
            frame.origin.x = start.origin.x + (target.origin.x - start.origin.x) * eased
            self.popoverAnchor.setFrame(frame, display: false)
            if progress >= 1 {
                timer.invalidate()
                self.popoverAnchorSlide = nil
                /* In case it didn't follow, or has to be fit on screen */
                if self.popover.isShown, let anchorView = self.popoverAnchor.contentView {
                    self.popover.positioningRect = anchorView.bounds
                }
            }
        }
        popoverAnchorSlide = timer
        RunLoop.main.add(timer, forMode: .common)
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
        stopPopoverAnchorSlide()
        if let frame = popoverAnchorFrame, let anchorView = popoverAnchor.contentView {
            popoverAnchor.setFrame(frame, display: false)
            popoverAnchor.orderFrontRegardless()
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }

    func popoverWillClose(_: Notification) {
        popoverCloseEventTime = NSApp.currentEvent?.timestamp
    }

    func popoverDidClose(_: Notification) {
        stopPopoverAnchorSlide()
        popoverAnchor.orderOut(nil)
    }

    private func stopPopoverAnchorSlide() {
        popoverReposition?.cancel()
        popoverReposition = nil
        popoverAnchorSlide?.invalidate()
        popoverAnchorSlide = nil
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
