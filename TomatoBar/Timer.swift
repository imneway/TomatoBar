import KeyboardShortcuts
import SwiftState
import SwiftUI

class TBTimer: ObservableObject {
    /* Defaults to the replaced "stopAfterBreak" preference */
    @AppStorage("manualNextPhase") var manualNextPhase =
        UserDefaults.standard.bool(forKey: "stopAfterBreak")
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") var workIntervalsInSet = 4
    // This preference is "hidden"
    @AppStorage("overrunTimeLimit") var overrunTimeLimit = -60.0
    /* Minutes between repeated reminders while waiting in manual mode, 0 disables them */
    @AppStorage("reminderInterval") var reminderInterval = 0
    /* Stop waiting in manual mode after this much overtime (seconds), also "hidden" */
    @AppStorage("overtimeLimit") var overtimeLimit = 3600.0
    /* Suggest starting the timer when working in the watched apps without it */
    @AppStorage("suggestStart") var suggestStart = true
    /* Minutes of work in the watched apps before the suggestion, also "hidden" */
    @AppStorage("suggestStartAfter") var suggestStartAfter = 5

    private var stateMachine = TBStateMachine(state: .idle)
    public let player = TBPlayer()
    private var consecutiveWorkIntervals: Int = 0
    private var notificationCenter = TBNotificationCenter()
    public let appWatcher = TBAppWatcher()
    private var finishTime: Date!
    private var lastReminderTime: Date?
    private var timerFormatter = DateComponentsFormatter()
    @Published var timeLeftString: String = ""
    @Published var timer: DispatchSourceTimer?
    @Published var state: TBStateMachineStates = .idle

    var isWaiting: Bool {
        stateMachine.state == .workDone || stateMachine.state == .restDone
    }

    init() {
        /*
         * State diagram (auto mode)
         *
         *                 start/stop
         *       +--------------+-------------+
         *       |              |             |
         *       |  start/stop  |  timerFired |
         *       V    |         |    |        |
         * +--------+ |  +--------+  | +--------+
         * | idle   |--->| work   |--->| rest   |
         * +--------+    +--------+    +--------+
         *                      A        |
         *                      |        |
         *                      +--------+
         *                 timerFired, skipRest
         *
         * In manual mode timerFired leads to workDone/restDone instead, where
         * the timer keeps counting overtime until the user starts the next
         * interval (startNext), skips the break (skipRest) or stops (startStop):
         *
         *   work --timerFired--> workDone --startNext--> rest
         *                           \---skipRest---> work
         *   rest --timerFired--> restDone --startNext--> work
         */
        stateMachine.addRoutes(event: .startStop, transitions: [
            .idle => .work, .work => .idle, .rest => .idle,
            .workDone => .idle, .restDone => .idle,
        ])
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .rest]) { _ in
            !self.manualNextPhase
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .workDone]) { _ in
            self.manualNextPhase
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .work]) { _ in
            !self.manualNextPhase
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .restDone]) { _ in
            self.manualNextPhase
        }
        stateMachine.addRoutes(event: .skipRest, transitions: [.rest => .work, .workDone => .work])
        stateMachine.addRoutes(event: .startNext, transitions: [.workDone => .rest, .restDone => .work])

        /*
         * "Finish" handlers are called when time interval ended
         * "End"    handlers are called when time interval ended or was cancelled
         */
        stateMachine.addAnyHandler(.any => .work, handler: onWorkStart)
        stateMachine.addAnyHandler(.work => .rest, order: 0, handler: onWorkFinish)
        stateMachine.addAnyHandler(.work => .workDone, order: 0, handler: onWorkFinish)
        stateMachine.addAnyHandler(.work => .any, order: 1, handler: onWorkEnd)
        stateMachine.addAnyHandler(.any => .workDone, handler: onWorkDone)
        stateMachine.addAnyHandler(.any => .rest, handler: onRestStart)
        stateMachine.addAnyHandler(.rest => .work, handler: onRestFinish)
        stateMachine.addAnyHandler(.any => .restDone, handler: onRestDone)
        stateMachine.addAnyHandler(.any => .idle, handler: onIdleStart)
        stateMachine.addAnyHandler(.any => .any, handler: { ctx in
            self.state = ctx.toState
            logger.append(event: TBLogEventTransition(fromContext: ctx))
            self.updateAppWatcher()
        })

        stateMachine.addErrorHandler { ctx in fatalError("state machine context: <\(ctx)>") }

        timerFormatter.unitsStyle = .positional
        timerFormatter.allowedUnits = [.minute, .second]
        timerFormatter.zeroFormattingBehavior = .pad

        KeyboardShortcuts.onKeyUp(for: .startStopTimer, action: startStop)
        notificationCenter.setActionHandler(handler: onNotificationAction)
        appWatcher.onThresholdReached = { [weak self] in self?.onStartSuggested() }
        updateAppWatcher()

        let aem: NSAppleEventManager = NSAppleEventManager.shared()
        aem.setEventHandler(self,
                            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                            forEventClass: AEEventClass(kInternetEventClass),
                            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.forKeyword(AEKeyword(keyDirectObject))?.stringValue else {
            print("url handling error: cannot get url")
            return
        }
        let url = URL(string: urlString)
        guard url != nil,
              let scheme = url!.scheme,
              let host = url!.host else {
            print("url handling error: cannot parse url")
            return
        }
        guard scheme.caseInsensitiveCompare("tomatobar") == .orderedSame else {
            print("url handling error: unknown scheme \(scheme)")
            return
        }
        switch host.lowercased() {
        case "startstop":
            startStop()
        default:
            print("url handling error: unknown command \(host)")
            return
        }
    }

    func startStop() {
        stateMachine <-! .startStop
    }

    func skipRest() {
        stateMachine <-! .skipRest
    }

    func startNext() {
        guard isWaiting else {
            return
        }
        stateMachine <-! .startNext
    }

    func updateTimeLeft() {
        guard finishTime != nil else {
            return
        }
        if isWaiting {
            timeLeftString = "+" + timerFormatter.string(from: finishTime, to: Date())!
        } else {
            timeLeftString = timerFormatter.string(from: Date(), to: finishTime)!
        }
        if timer != nil, showTimerInMenuBar {
            TBStatusItem.shared.setTitle(title: timeLeftString)
        } else {
            TBStatusItem.shared.setTitle(title: nil)
        }
    }

    private func startTimer(seconds: Int) {
        finishTime = Date().addingTimeInterval(TimeInterval(seconds))

        timer?.cancel()
        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer!.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer!.setEventHandler(handler: onTimerTick)
        timer!.setCancelHandler(handler: onTimerCancel)
        timer!.resume()
    }

    private func stopTimer() {
        timer!.cancel()
        timer = nil
    }

    private func onTimerTick() {
        /* Cannot publish updates from background thread */
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
            if isWaiting {
                /* Most likely forgotten, counting further makes no sense */
                if Date().timeIntervalSince(finishTime) > overtimeLimit {
                    stateMachine <-! .startStop
                } else {
                    remindIfNeeded()
                }
                return
            }
            /* A tick can be queued right before the timer is stopped */
            guard stateMachine.state == .work || stateMachine.state == .rest else {
                return
            }
            let timeLeft = finishTime.timeIntervalSince(Date())
            if timeLeft <= 0 {
                /*
                 Ticks can be missed during the machine sleep.
                 Stop the timer if it goes beyond an overrun time limit.
                 In manual mode wait for the user anyway, counting overtime
                 from the planned finish time, unless it's already over the limit.
                 */
                let limit = manualNextPhase ? -overtimeLimit : overrunTimeLimit
                if timeLeft < limit {
                    stateMachine <-! .startStop
                } else {
                    stateMachine <-! .timerFired
                }
            }
        }
    }

    private func onTimerCancel() {
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
        }
    }

    private func remindIfNeeded() {
        guard reminderInterval > 0, let last = lastReminderTime,
              Date().timeIntervalSince(last) >= TimeInterval(reminderInterval * 60)
        else {
            return
        }
        lastReminderTime = Date()
        player.playDing()
        if stateMachine.state == .workDone {
            sendWorkDoneNotification()
        } else {
            sendRestDoneNotification()
        }
    }

    private func onNotificationAction(action: TBNotification.Action) {
        /* Stale notifications may still be around, check the current state */
        let state = stateMachine.state
        switch action {
        case .skipRest where state == .rest || state == .workDone:
            skipRest()
        case .startRest where state == .workDone, .startWork where state == .restDone:
            startNext()
        case .startWork where state == .idle:
            startStop()
        default:
            break
        }
    }

    private var isLongRestDue: Bool {
        consecutiveWorkIntervals >= workIntervalsInSet
    }

    private func restStartBody() -> String {
        isLongRestDue ?
            NSLocalizedString("TBTimer.onRestStart.long.body", comment: "Long break body") :
            NSLocalizedString("TBTimer.onRestStart.short.body", comment: "Short break body")
    }

    private func sendWorkDoneNotification() {
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
            body: restStartBody(),
            category: .workDone
        )
    }

    private func sendRestDoneNotification() {
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestFinish.title", comment: "Break is over title"),
            body: NSLocalizedString("TBTimer.onRestFinish.body", comment: "Break is over body"),
            category: .restDone
        )
    }

    /* Only watch the apps while the timer is not running */
    func updateAppWatcher() {
        if suggestStart, stateMachine.state == .idle {
            appWatcher.threshold = TimeInterval(suggestStartAfter * 60)
            appWatcher.start()
        } else {
            appWatcher.stop()
        }
    }

    private func onStartSuggested() {
        guard stateMachine.state == .idle else {
            return
        }
        logger.append(event: TBLogEventStartSuggested())
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onStartSuggested.title", comment: "Start suggestion title"),
            body: NSLocalizedString("TBTimer.onStartSuggested.body", comment: "Start suggestion body"),
            category: .startSuggested
        )
    }

    private func onWorkStart(context ctx: TBStateMachine.Context) {
        /* Clear the start suggestion or the waiting notification */
        notificationCenter.clear()
        if ctx.fromState == .workDone, isLongRestDue {
            /* Long break was skipped */
            consecutiveWorkIntervals = 0
        }
        TBStatusItem.shared.setIcon(name: .work)
        player.playWindup()
        player.startTicking()
        startTimer(seconds: workIntervalLength * 60)
    }

    private func onWorkFinish(context _: TBStateMachine.Context) {
        consecutiveWorkIntervals += 1
        player.playDing()
    }

    private func onWorkEnd(context _: TBStateMachine.Context) {
        player.stopTicking()
    }

    private func onWorkDone(context _: TBStateMachine.Context) {
        lastReminderTime = Date()
        sendWorkDoneNotification()
    }

    private func onRestStart(context ctx: TBStateMachine.Context) {
        if ctx.fromState == .work {
            notificationCenter.send(
                title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
                body: restStartBody(),
                category: .restStarted
            )
        } else {
            /* Started manually from a notification or the popover */
            notificationCenter.clear()
        }
        var length = shortRestIntervalLength
        var imgName = NSImage.Name.shortRest
        if isLongRestDue {
            length = longRestIntervalLength
            imgName = .longRest
            consecutiveWorkIntervals = 0
        }
        TBStatusItem.shared.setIcon(name: imgName)
        startTimer(seconds: length * 60)
    }

    private func onRestFinish(context ctx: TBStateMachine.Context) {
        if ctx.event == .skipRest {
            return
        }
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestFinish.title", comment: "Break is over title"),
            body: NSLocalizedString("TBTimer.onRestFinish.body", comment: "Break is over body"),
            category: .restFinished
        )
    }

    private func onRestDone(context _: TBStateMachine.Context) {
        lastReminderTime = Date()
        player.playDing()
        sendRestDoneNotification()
    }

    private func onIdleStart(context _: TBStateMachine.Context) {
        stopTimer()
        notificationCenter.clear()
        lastReminderTime = nil
        TBStatusItem.shared.setIcon(name: .idle)
        consecutiveWorkIntervals = 0
    }
}
