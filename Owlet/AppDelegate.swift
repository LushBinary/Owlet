//
//  AppDelegate.swift
//  Owlet
//
//  Wires everything together: creates the PowerManager and StatusBarController,
//  configures the app as a background (accessory) agent, and guarantees that all
//  power assertions are released and clamshell mode is reset on sleep and quit.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let power = PowerManager()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders alongside LSUIElement: no Dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)

        // Build the menu-bar UI.
        statusBar = StatusBarController(power: power)

        // Release IOKit assertions if the machine is about to sleep for any reason
        // (e.g. the user chose Apple menu > Sleep). Clamshell mode is a persistent
        // system setting the user explicitly enabled, so we leave it until quit.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil)
    }

    @objc private func systemWillSleep() {
        power.stopKeepAwake()
    }

    /// On quit we release assertions and reset `disablesleep` to 0. Resetting
    /// clamshell needs admin rights (an async prompt), so defer termination until
    /// the cleanup completes.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Nothing privileged to undo -> terminate immediately.
        if !power.isClamshellActive {
            power.stopKeepAwake()
            return .terminateNow
        }

        power.cleanupForQuit(resetClamshell: true) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Final safety net for the userland assertions (no admin prompt here).
        power.stopKeepAwake()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
