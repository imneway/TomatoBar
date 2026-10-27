import AppKit

/*
 Bundle identifiers (or their prefixes) of the apps whose use means the user
 is working and probably forgot to start the timer
 */
let defaultWatchedApps = [
    "com.figma.Desktop",
    "org.blenderfoundation.blender",
    "com.adobe.AfterEffects",
    "com.adobe.Photoshop",
    "com.tinyspeck.slackmacgap",
    "com.openai.chat",
    "com.openai.codex",
    "com.anthropic.claudefordesktop",
]

/*
 Tracks how long the user has been working in the watched apps and reports
 when it's time to suggest starting a work interval.

 A work session accumulates while a watched app is frontmost. Switching to
 another app pauses the session, it goes on if the user comes back within
 the grace period and starts over otherwise. Going idle, sleep and screen
 lock start it over too.
 */
class TBAppWatcher {
    static let watchedAppsKey = "watchedApps"

    /* Seconds of work in the watched apps after which the suggestion is made */
    var threshold: TimeInterval = 5 * 60
    /* Called on the main thread when the threshold is reached */
    var onThresholdReached: (() -> Void)?

    private let sampleInterval: TimeInterval = 5
    /* Time away from the watched apps that doesn't break the session */
    private let gracePeriod: TimeInterval = 90
    /* No input for this long means the user has left, even if the app is still in front */
    private let idleLimit: TimeInterval = 3 * 60
    /* Minimum time between suggestions */
    private let suggestionInterval: TimeInterval = 15 * 60

    private var timer: Timer?
    private var sessionSeconds: TimeInterval = 0
    private var awaySince: Date?
    private var lastSampleTime: Date?
    private var lastSuggestionTime: Date?
    private var observers: [NSObjectProtocol] = []

    var isRunning: Bool {
        timer != nil
    }

    init() {
        UserDefaults.standard.register(defaults: [Self.watchedAppsKey: defaultWatchedApps])
    }

    deinit {
        stop()
    }

    static var watchedApps: [String] {
        UserDefaults.standard.stringArray(forKey: watchedAppsKey) ?? defaultWatchedApps
    }

    func start() {
        guard timer == nil else {
            return
        }
        resetSession()
        lastSampleTime = Date()
        let timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        /* Keep sampling while the popover is open */
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.resetSession()
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.resetSession()
        })
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        resetSession()
    }

    private func resetSession() {
        sessionSeconds = 0
        awaySince = nil
    }

    private var isWatchedAppActive: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return Self.watchedApps.contains { bundleID == $0 || bundleID.hasPrefix($0) }
    }

    /* Seconds since the last keyboard or mouse input */
    private var idleSeconds: TimeInterval {
        let eventTypes: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .scrollWheel, .keyDown, .flagsChanged,
        ]
        return eventTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? 0
    }

    private func sample() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleTime ?? now)
        lastSampleTime = now

        /* Samples are missed during the machine sleep */
        if elapsed > sampleInterval * 3 || idleSeconds > idleLimit {
            resetSession()
            return
        }

        if isWatchedAppActive {
            /* Came back too late, the sample at the edge of the grace period kept the session */
            if let awaySince = awaySince, now.timeIntervalSince(awaySince) > gracePeriod {
                resetSession()
            }
            awaySince = nil
            sessionSeconds += elapsed
        } else {
            let awaySince = self.awaySince ?? now
            self.awaySince = awaySince
            if now.timeIntervalSince(awaySince) > gracePeriod {
                resetSession()
            }
            return
        }

        guard sessionSeconds >= threshold else {
            return
        }
        if let last = lastSuggestionTime, now.timeIntervalSince(last) < suggestionInterval {
            return
        }
        lastSuggestionTime = now
        /* Don't suggest again until the user comes back after a break */
        resetSession()
        onThresholdReached?()
    }
}
