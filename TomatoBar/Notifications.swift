import UserNotifications

enum TBNotification {
    enum Category: String {
        case restStarted, restFinished, workDone, restDone
    }

    enum Action: String {
        case skipRest, startRest, startWork
    }
}

typealias TBNotificationHandler = (TBNotification.Action) -> Void

class TBNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    private var center = UNUserNotificationCenter.current()
    private var handler: TBNotificationHandler?

    override init() {
        super.init()

        center.requestAuthorization(
            options: [.alert]
        ) { _, error in
            if error != nil {
                print("Error requesting notification authorization: \(error!)")
            }
        }

        center.delegate = self

        let actionSkipRest = UNNotificationAction(
            identifier: TBNotification.Action.skipRest.rawValue,
            title: NSLocalizedString("TBTimer.onRestStart.skip.title", comment: "Skip"),
            options: []
        )
        let actionStartRest = UNNotificationAction(
            identifier: TBNotification.Action.startRest.rawValue,
            title: NSLocalizedString("TBNotification.startRest.title", comment: "Start break"),
            options: []
        )
        let actionSkipRestManual = UNNotificationAction(
            identifier: TBNotification.Action.skipRest.rawValue,
            title: NSLocalizedString("TBNotification.skipRest.title", comment: "Skip break"),
            options: []
        )
        let actionStartWork = UNNotificationAction(
            identifier: TBNotification.Action.startWork.rawValue,
            title: NSLocalizedString("TBNotification.startWork.title", comment: "Start work"),
            options: []
        )
        let restStartedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.restStarted.rawValue,
            actions: [actionSkipRest],
            intentIdentifiers: []
        )
        let restFinishedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.restFinished.rawValue,
            actions: [],
            intentIdentifiers: []
        )
        let workDoneCategory = UNNotificationCategory(
            identifier: TBNotification.Category.workDone.rawValue,
            actions: [actionStartRest, actionSkipRestManual],
            intentIdentifiers: []
        )
        let restDoneCategory = UNNotificationCategory(
            identifier: TBNotification.Category.restDone.rawValue,
            actions: [actionStartWork],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            restStartedCategory,
            restFinishedCategory,
            workDoneCategory,
            restDoneCategory,
        ])
    }

    func setActionHandler(handler: @escaping TBNotificationHandler) {
        self.handler = handler
    }

    /* Show banners even when the app is active (e.g. popover is open) */
    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent _: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void)
    {
        defer { completionHandler() }

        var action = TBNotification.Action(rawValue: response.actionIdentifier)
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            /* Clicking the notification body starts the next interval */
            let category = response.notification.request.content.categoryIdentifier
            switch TBNotification.Category(rawValue: category) {
            case .workDone:
                action = .startRest
            case .restDone:
                action = .startWork
            default:
                break
            }
        }

        guard let action = action, let handler = handler else {
            return
        }
        DispatchQueue.main.async {
            handler(action)
        }
    }

    func send(title: String, body: String, category: TBNotification.Category) {
        /* Replace stale notifications, so only the current one stays on screen */
        clear()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if error != nil {
                print("Error adding notification: \(error!)")
            }
        }
    }

    func clear() {
        center.removeAllDeliveredNotifications()
    }
}
