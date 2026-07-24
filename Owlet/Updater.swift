//
//  Updater.swift
//  Owlet
//
//  Wraps Sparkle's standard updater so the menu bar can offer "Check for
//  Updates…". Owlet is distributed directly (Developer ID, not the App Store),
//  so Sparkle handles finding, verifying, and installing new versions from the
//  appcast declared in Info.plist (`SUFeedURL` + `SUPublicEDKey`).
//
//  Sparkle only *installs* updates on a properly signed + notarized build, but
//  the controller is safe to create in any build; on unsigned builds a check
//  simply reports that no valid update could be applied.
//

import AppKit
import Sparkle

@MainActor
final class Updater {

    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        // `startingUpdater: true` begins the scheduled-check machinery immediately;
        // the standard user driver presents Sparkle's normal update windows (which
        // work for a menu-bar/accessory app too).
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    /// True when the updater is in a state where a manual check is allowed.
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    /// Manually check for updates (brings its own UI, prompting the user).
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }
}
