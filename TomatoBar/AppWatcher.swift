import AppKit

/* An app whose use means the user is working and probably forgot to start the timer */
struct TBWatchedApp: Codable, Identifiable, Equatable {
    /* Bundle identifier or its prefix, Adobe apps append a version suffix */
    let id: String
    let name: String

    func matches(bundleID: String) -> Bool {
        bundleID == id || bundleID.hasPrefix(id)
    }

    /* Resolved from the installed or running app, so the name follows the system language */
    var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) ??
            NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier.map(matches) ?? false }?.bundleURL
    }

    var displayName: String {
        url.map { FileManager.default.displayName(atPath: $0.path) } ?? name
    }

    var icon: NSImage {
        url.map { NSWorkspace.shared.icon(forFile: $0.path) } ??
            NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!
    }

    private static let plistKeys = ["CFBundleDisplayName", "CFBundleName"]

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init?(url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            return nil
        }
        let name = Self.plistKeys.lazy
            .compactMap { bundle.object(forInfoDictionaryKey: $0) as? String }
            .first ?? url.deletingPathExtension().lastPathComponent
        self.init(id: id, name: name)
    }
}

let defaultWatchedApps = [
    TBWatchedApp(id: "com.figma.Desktop", name: "Figma"),
    TBWatchedApp(id: "org.blenderfoundation.blender", name: "Blender"),
    TBWatchedApp(id: "com.adobe.AfterEffects", name: "After Effects"),
    TBWatchedApp(id: "com.adobe.Photoshop", name: "Photoshop"),
    TBWatchedApp(id: "com.tinyspeck.slackmacgap", name: "Slack"),
    TBWatchedApp(id: "com.openai.chat", name: "ChatGPT"),
    TBWatchedApp(id: "com.openai.codex", name: "ChatGPT"),
    TBWatchedApp(id: "com.anthropic.claudefordesktop", name: "Claude"),
]

/*
 Tracks how long the user has been working in the watched apps and reports
 when it's time to suggest starting a work interval.

 A work session accumulates while a watched app is frontmost. Switching to
 another app pauses the session, it goes on if the user comes back within
 the grace period and starts over otherwise. Going idle, sleep and screen
 lock start it over too.
 */
class TBAppWatcher: ObservableObject {
    private static let watchedAppsKey = "watchedApps"

    @Published var watchedApps: [TBWatchedApp] {
        didSet {
            let data = try? JSONEncoder().encode(watchedApps)
            UserDefaults.standard.set(data, forKey: Self.watchedAppsKey)
        }
    }

    /* Seconds of work in the watched apps after which the suggestion is made */
    var threshold: TimeInterval = 5 * 60
    /* Called on the main thread when the threshold is reached */
    var onThresholdReached: (() -> Void)?

    /* Time away from the watched apps that doesn't break the session */
    var gracePeriod: TimeInterval = 90

    private let sampleInterval: TimeInterval = 5
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
        if let data = UserDefaults.standard.data(forKey: Self.watchedAppsKey),
           let apps = try? JSONDecoder().decode([TBWatchedApp].self, from: data) {
            watchedApps = apps
        } else {
            watchedApps = defaultWatchedApps
        }
    }

    func add(url: URL) {
        guard let app = TBWatchedApp(url: url), !watchedApps.contains(where: { $0.id == app.id }) else {
            return
        }
        watchedApps.append(app)
    }

    func remove(id: String) {
        watchedApps.removeAll { $0.id == id }
    }

    /* Regular apps running now that aren't watched yet, to pick from */
    var runningAppsToAdd: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier, app.bundleURL != nil
            else {
                return false
            }
            return !watchedApps.contains { $0.matches(bundleID: bundleID) }
        }.sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    deinit {
        stop()
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
        return watchedApps.contains { $0.matches(bundleID: bundleID) }
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
