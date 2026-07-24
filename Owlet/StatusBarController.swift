//
//  StatusBarController.swift
//  Owlet
//
//  Owns the NSStatusItem (the menu-bar icon) and its NSMenu. Translates menu
//  clicks into PowerManager calls and reflects PowerManager state back into the
//  icon (filled = active, outline = idle) and a status line.
//

import AppKit

@MainActor
final class StatusBarController: NSObject {

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let power: PowerManager

    // Duration options offered in the "Keep Awake For" submenu.
    private let durations: [KeepAwakeDuration] = [
        .minutes(30), .minutes(60), .minutes(120), .indefinite
    ]

    // Auto-revert options offered in the "Keep Clamshell For" submenu
    // (longer defaults than keep-awake since clamshell sessions tend to be longer).
    private let clamshellDurations: [KeepAwakeDuration] = [
        .minutes(60), .minutes(120), .minutes(240), .indefinite
    ]

    init(power: PowerManager) {
        self.power = power
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        statusItem.menu = menu

        // Refresh the UI whenever the power state changes.
        power.onChange = { [weak self] in self?.refresh() }

        // Warn if clamshell was left on from a previous session / crash.
        power.onLeftoverClamshellDetected = { [weak self] in self?.warnLeftoverClamshell() }

        refresh()
    }

    // MARK: - Rendering

    /// Update the menu-bar icon and repopulate the menu to reflect current state.
    private func refresh() {
        let active = power.isKeepAwakeActive || power.isClamshellActive

        if let button = statusItem.button {
            // Custom owl glyph generated in OwletSymbol: filled when active,
            // outline when idle. It's a template image, so it adapts to the menu bar.
            let image = OwletSymbol.image(active: active)
            image.accessibilityDescription = active ? "Owlet — awake" : "Owlet — idle"
            button.image = image
            button.toolTip = statusText
        }

        populate(menu)
    }

    /// Human-readable summary shown at the top of the menu and as the tooltip.
    private var statusText: String {
        var parts: [String] = []

        parts.append(power.isKeepAwakeActive ? "Awake" : "Sleep allowed")

        if power.isClamshellActive {
            parts.append("Clamshell ON")
        }

        if let remaining = power.remainingSeconds {
            parts.append("\(minutesLeft(remaining)) min left")
        } else if power.activeDuration == .indefinite && power.isKeepAwakeActive {
            parts.append("no timer")
        }

        if let clamshellRemaining = power.clamshellRemainingSeconds {
            parts.append("clamshell \(minutesLeft(clamshellRemaining)) min left")
        }

        return parts.joined(separator: " · ")
    }

    private func minutesLeft(_ seconds: TimeInterval) -> Int {
        Int((seconds / 60).rounded(.up))
    }

    // MARK: - Menu construction

    /// Clear and rebuild the menu items in place (safe during menuNeedsUpdate).
    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status header (disabled, purely informational).
        let header = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Keep Awake toggle.
        let keepAwake = NSMenuItem(title: "Keep Awake",
                                   action: #selector(toggleKeepAwake),
                                   keyEquivalent: "")
        keepAwake.target = self
        keepAwake.state = power.isKeepAwakeActive ? .on : .off
        // Hovering any item shows a plain-language explanation + any risk.
        keepAwake.toolTip = Help.keepAwake
        menu.addItem(keepAwake)

        // "Keep Awake For" submenu with timer options.
        let timerParent = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        timerParent.toolTip = Help.timer
        let timerMenu = NSMenu()
        for duration in durations {
            let item = NSMenuItem(title: duration.label,
                                  action: #selector(selectDuration(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = boxed(duration)
            // Check the currently active duration.
            item.state = (power.isKeepAwakeActive && power.activeDuration == duration) ? .on : .off
            item.toolTip = Help.timer
            timerMenu.addItem(item)
        }
        timerParent.submenu = timerMenu
        menu.addItem(timerParent)

        menu.addItem(.separator())

        // Clamshell toggle.
        let clamshell = NSMenuItem(title: "Allow Lid-Closed (Clamshell) Mode",
                                   action: #selector(toggleClamshell),
                                   keyEquivalent: "")
        clamshell.target = self
        clamshell.state = power.isClamshellActive ? .on : .off
        clamshell.toolTip = Help.clamshell
        menu.addItem(clamshell)

        // "Keep Clamshell For" submenu — enables clamshell (prompting for admin)
        // and schedules an automatic revert after the chosen duration.
        let clamshellTimerParent = NSMenuItem(title: "Keep Clamshell For", action: nil, keyEquivalent: "")
        clamshellTimerParent.toolTip = Help.clamshellTimer
        let clamshellMenu = NSMenu()
        for duration in clamshellDurations {
            let item = NSMenuItem(title: duration.label,
                                  action: #selector(selectClamshellDuration(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = boxed(duration)
            item.state = (power.isClamshellActive && power.activeClamshellDuration == duration) ? .on : .off
            item.toolTip = Help.clamshellTimer
            clamshellMenu.addItem(item)
        }
        clamshellTimerParent.submenu = clamshellMenu
        menu.addItem(clamshellTimerParent)

        menu.addItem(.separator())

        // Launch at Login toggle (SMAppService).
        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLaunchAtLogin),
                               keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        login.toolTip = Help.launchAtLogin
        menu.addItem(login)

        // Inline help: expands into the full description of every feature + risks.
        let help = NSMenuItem(title: "What do these do?", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        help.toolTip = "Show a full explanation of each feature and its risks."
        menu.addItem(help)

        menu.addItem(.separator())

        // Quit.
        let quit = NSMenuItem(title: "Quit Owlet",
                              action: #selector(quit),
                              keyEquivalent: "q")
        quit.target = self
        quit.toolTip = Help.quit
        menu.addItem(quit)
    }

    /// Wrap a duration in an Int so it can live in `representedObject`.
    /// 0 == indefinite, otherwise the minute count.
    private func boxed(_ duration: KeepAwakeDuration) -> NSNumber {
        switch duration {
        case .indefinite:        return NSNumber(value: 0)
        case .minutes(let m):    return NSNumber(value: m)
        }
    }

    private func unboxed(_ object: Any?) -> KeepAwakeDuration? {
        guard let number = object as? NSNumber else { return nil }
        let value = number.intValue
        return value == 0 ? .indefinite : .minutes(value)
    }

    // MARK: - Actions

    @objc private func toggleKeepAwake() {
        power.toggleKeepAwake()
    }

    @objc private func toggleClamshell() {
        let turningOn = !power.isClamshellActive
        power.setClamshell(turningOn) { [weak self] result in
            switch result {
            case .success, .cancelled:
                break                              // onChange already refreshed the UI
            case .failed(let message):
                self?.presentError(message)
            }
        }
    }

    @objc private func selectDuration(_ sender: NSMenuItem) {
        guard let duration = unboxed(sender.representedObject) else { return }
        // Selecting the already-active duration turns keep-awake off.
        if power.isKeepAwakeActive && power.activeDuration == duration {
            power.stopKeepAwake()
        } else {
            power.startKeepAwake(duration: duration)
        }
    }

    @objc private func selectClamshellDuration(_ sender: NSMenuItem) {
        guard let duration = unboxed(sender.representedObject) else { return }
        // Re-selecting the active clamshell duration turns clamshell off.
        if power.isClamshellActive && power.activeClamshellDuration == duration {
            power.setClamshell(false) { [weak self] result in
                if case .failed(let message) = result { self?.presentError(message) }
            }
        } else {
            // Enables clamshell (prompts for admin) and schedules the auto-revert.
            power.setClamshell(true, duration: duration) { [weak self] result in
                if case .failed(let message) = result { self?.presentError(message) }
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let turningOn = !LoginItem.isEnabled
        if let error = LoginItem.setEnabled(turningOn) {
            presentError(error)
        } else if turningOn && LoginItem.requiresApproval {
            let alert = NSAlert()
            alert.messageText = "Approve Owlet in Login Items"
            alert.informativeText = "macOS needs you to allow Owlet under System Settings > General > Login Items."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Ask the user whether to reset a leftover clamshell setting found at launch.
    private func warnLeftoverClamshell() {
        let alert = NSAlert()
        alert.messageText = "Clamshell mode was left on"
        alert.informativeText = """
        Owlet found lid-closed (clamshell) mode still enabled from a previous \
        session. Your Mac won't sleep until it's turned off. Reset it now?
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset Now")
        alert.addButton(withTitle: "Keep It On")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            power.setClamshell(false) { [weak self] result in
                if case .failed(let message) = result { self?.presentError(message) }
            }
        }
    }

    /// Show a single panel describing every feature and its risks.
    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "What Owlet does"
        alert.informativeText = Help.fullExplanation
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        // Bring the app forward so the panel isn't lost behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Error UI

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't change clamshell setting"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Help text

/// Plain-language descriptions of each feature and its risks. Used both as
/// per-item tooltips and in the "What do these do?" panel.
private enum Help {
    static let keepAwake = """
    Keep Awake: stops your Mac and its display from going to sleep while idle. \
    It uses a temporary power "assertion" (the same mechanism as coffee/caffeine \
    apps) and changes no system settings. Risk: none meaningful — it's fully \
    reversible and clears automatically on Quit, on actual sleep, or when a timer ends.
    """

    static let clamshell = """
    Allow Lid-Closed (Clamshell) Mode: keeps the Mac running with the lid shut by \
    disabling sleep system-wide (pmset disablesleep). Requires your admin password. \
    Risks: (1) with the lid closed the Mac loses its main airflow path, so it can run \
    hot under load — keep it on AC power and, ideally, on a hard surface; (2) it's a \
    system-wide setting, not just for Owlet, so nothing will sleep the Mac until it's \
    turned off. Owlet resets it to normal automatically when you Quit.
    """

    static let timer = """
    Keep Awake For…: stays awake for the chosen duration, then automatically releases \
    the lock and lets the Mac sleep normally. "Indefinitely" stays awake until you turn \
    it off or Quit. Risk: none — this only controls the Keep Awake assertion.
    """

    static let clamshellTimer = """
    Keep Clamshell For…: turns on lid-closed mode (asks for your admin password) and \
    automatically reverts it after the chosen time. Note: reverting also needs admin, \
    so when the timer fires macOS shows a password prompt — if the Mac is unattended, \
    clamshell stays on until someone confirms it.
    """

    static let launchAtLogin = """
    Launch at Login: starts Owlet automatically when you log in, so it's ready in the \
    menu bar without opening it manually. macOS may ask you to approve it once under \
    System Settings > General > Login Items.
    """

    static let quit = """
    Quit Owlet: releases all keep-awake locks and restores normal sleep behavior \
    (including turning clamshell mode back off) before the app exits.
    """

    static let fullExplanation = """
    KEEP AWAKE
    \(keepAwake)

    KEEP AWAKE FOR…
    \(timer)

    ALLOW LID-CLOSED (CLAMSHELL) MODE
    \(clamshell)

    KEEP CLAMSHELL FOR…
    \(clamshellTimer)

    LAUNCH AT LOGIN
    \(launchAtLogin)

    QUIT
    \(quit)

    Note: clamshell behavior follows macOS rules — it's most reliable on AC power, and \
    some Mac models still expect an external display to be attached.
    """
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    /// Repopulate just before the menu opens so the countdown / status is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }
}
