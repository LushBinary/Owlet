//
//  Notifier.swift
//  Owlet
//
//  Thin wrapper over UNUserNotificationCenter used to tell the user when Owlet
//  changes state on its own — a keep-awake timer ending, clamshell auto-reverting,
//  or clamshell being disabled because the Mac went onto battery. Owlet is a
//  menu-bar-only (accessory) app with no windows, so a banner is the only way to
//  surface these background events.
//

import UserNotifications
import os

/// App-wide notification helper. `Notifier.shared.start()` is called once at
/// launch to request permission and register as the presentation delegate;
/// `post(title:body:)` fires a banner (silently dropped if permission is denied).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    static let shared = Notifier()

    private let log = Logger(subsystem: "com.lushbinary.Owlet", category: "Notifier")

    private override init() { super.init() }

    /// Request notification permission and become the presentation delegate so
    /// banners appear even while Owlet is the "frontmost" (accessory) app.
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                self?.log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else {
                self?.log.info("Notification authorization granted: \(granted, privacy: .public)")
            }
        }
    }

    /// Post a simple banner. No-op if the user hasn't granted permission.
    func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content,
                                                trigger: nil)
            center.add(request)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner even when Owlet is active, since it has no window to fall
    /// back to.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
