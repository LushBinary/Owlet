//
//  LoginItem.swift
//  Owlet
//
//  Thin wrapper over SMAppService (macOS 13+) for the "Launch at Login" toggle.
//  Registering adds Owlet as a login item so it's running whenever you need it;
//  unregistering removes it.
//

import ServiceManagement
import os

enum LoginItem {

    private static let log = Logger(subsystem: "com.lushbinary.Owlet", category: "LoginItem")

    /// Whether Owlet is currently set to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// The user may have to approve the login item in System Settings > General >
    /// Login Items. This surfaces that case so the UI can guide them.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Turn the login item on/off. Returns nil on success, or an error message.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            log.error("Login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }
}
