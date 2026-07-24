//
//  PowerManager.swift
//  Owlet
//
//  Owns all of the "keep the Mac awake" logic:
//   1. IOKit power assertions to prevent idle system + display sleep.
//   2. Privileged `pmset -a disablesleep` calls to allow lid-closed (clamshell) mode.
//   3. An optional auto-release timer (30 min / 1 hr / 2 hr / indefinite).
//
//  The type is MainActor-isolated (the project's default) so all state mutation
//  and UI callbacks happen on the main thread. The only work pushed to a
//  background queue is launching `osascript`/`pmset`, whose result is hopped
//  back to the main actor.
//

import Foundation
import IOKit.pwr_mgt
import os

/// How long a "keep awake" session should last before auto-releasing.
enum KeepAwakeDuration: Equatable {
    case minutes(Int)
    case indefinite

    /// Human-readable label used in the menu.
    var label: String {
        switch self {
        case .minutes(let m) where m % 60 == 0: return "\(m / 60) hr"
        case .minutes(let m):                   return "\(m) min"
        case .indefinite:                       return "Indefinitely"
        }
    }
}

/// Result of a privileged clamshell toggle so the UI can react precisely.
enum ClamshellResult {
    case success
    case cancelled          // user dismissed the admin password prompt
    case failed(String)     // any other failure, with a message
}

@MainActor
final class PowerManager {

    // MARK: - Observable state (read by StatusBarController)

    /// True while at least one IOKit power assertion is held.
    private(set) var isKeepAwakeActive = false

    /// True while `SleepDisabled` is set (lid-closed / clamshell mode).
    private(set) var isClamshellActive = false

    /// When the current timed session ends. `nil` means no timer / indefinite.
    private(set) var timerEndDate: Date?

    /// The duration the user selected for the current session (for the checkmark in the menu).
    private(set) var activeDuration: KeepAwakeDuration?

    /// When the clamshell auto-revert timer ends. `nil` means no timer / indefinite.
    private(set) var clamshellTimerEndDate: Date?

    /// The clamshell auto-revert duration the user selected (for the menu checkmark).
    private(set) var activeClamshellDuration: KeepAwakeDuration?

    /// Called on the main thread whenever any state changes so the UI can refresh.
    var onChange: (() -> Void)?

    /// Called on the main thread once, if `disablesleep` was already ON at launch
    /// (i.e. left over from a previous session / crash and not set by us).
    var onLeftoverClamshellDetected: (() -> Void)?

    // MARK: - Private state

    /// IOKit assertion IDs. `kIOPMNullAssertionID` (0) means "not held".
    private var systemSleepAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var displaySleepAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

    /// Fires once to auto-release a timed keep-awake session.
    private var expiryTimer: Timer?

    /// Fires once to auto-revert clamshell mode.
    private var clamshellExpiryTimer: Timer?

    /// Guards the "leftover clamshell" check so it only fires on the first sync.
    private var didInitialSync = false

    private let log = Logger(subsystem: "com.lushbinary.Owlet", category: "PowerManager")

    // MARK: - Lifecycle

    init() {
        // On launch, read the real system SleepDisabled state so the UI matches reality.
        refreshClamshellStateFromSystem()
    }

    // MARK: - Keep Awake (IOKit power assertions)

    /// Remaining seconds for a timed session, or nil if indefinite / inactive.
    var remainingSeconds: TimeInterval? {
        guard let end = timerEndDate else { return nil }
        return max(0, end.timeIntervalSinceNow)
    }

    /// Toggle the plain "keep awake" (indefinite) power assertion.
    func toggleKeepAwake() {
        if isKeepAwakeActive {
            stopKeepAwake()
        } else {
            startKeepAwake(duration: .indefinite)
        }
    }

    /// Begin holding power assertions, optionally auto-releasing after `duration`.
    func startKeepAwake(duration: KeepAwakeDuration) {
        createAssertionsIfNeeded()

        // (Re)configure the auto-release timer.
        invalidateTimer()
        switch duration {
        case .indefinite:
            timerEndDate = nil
        case .minutes(let minutes):
            let interval = TimeInterval(minutes * 60)
            timerEndDate = Date().addingTimeInterval(interval)
            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                // Timer callbacks are delivered on the main run loop; hop to the
                // main actor to satisfy isolation and release the assertions.
                Task { @MainActor in self?.timerDidExpire() }
            }
            RunLoop.main.add(timer, forMode: .common)
            expiryTimer = timer
        }

        activeDuration = duration
        notifyChange()
    }

    /// Release all power assertions and cancel any pending timer.
    func stopKeepAwake() {
        releaseAssertions()
        invalidateTimer()
        timerEndDate = nil
        activeDuration = nil
        notifyChange()
    }

    private func timerDidExpire() {
        log.info("Keep-awake timer expired; releasing assertions.")
        stopKeepAwake()
    }

    /// Create the two IOKit assertions if we don't already hold them.
    ///
    /// `IOPMAssertionCreateWithName` registers a named assertion with the power
    /// management subsystem. While the assertion is held the system will not
    /// enter the corresponding idle-sleep state. We hold two:
    ///   - kIOPMAssertionTypePreventUserIdleSystemSleep: the machine won't idle-sleep.
    ///   - kIOPMAssertionTypePreventUserIdleDisplaySleep: the display won't sleep,
    ///     which also implicitly keeps the system awake.
    private func createAssertionsIfNeeded() {
        let reason = "Owlet keeping the Mac awake" as CFString

        if systemSleepAssertionID == IOPMAssertionID(kIOPMNullAssertionID) {
            var id = IOPMAssertionID(kIOPMNullAssertionID)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &id)
            if result == kIOReturnSuccess {
                systemSleepAssertionID = id
            } else {
                log.error("Failed to create system-sleep assertion: \(result, privacy: .public)")
            }
        }

        if displaySleepAssertionID == IOPMAssertionID(kIOPMNullAssertionID) {
            var id = IOPMAssertionID(kIOPMNullAssertionID)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &id)
            if result == kIOReturnSuccess {
                displaySleepAssertionID = id
            } else {
                log.error("Failed to create display-sleep assertion: \(result, privacy: .public)")
            }
        }

        isKeepAwakeActive = (systemSleepAssertionID != IOPMAssertionID(kIOPMNullAssertionID))
            || (displaySleepAssertionID != IOPMAssertionID(kIOPMNullAssertionID))
    }

    /// Release both assertions via `IOPMAssertionRelease`, which tells power
    /// management we no longer need to block sleep. Always safe to call.
    private func releaseAssertions() {
        if systemSleepAssertionID != IOPMAssertionID(kIOPMNullAssertionID) {
            IOPMAssertionRelease(systemSleepAssertionID)
            systemSleepAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
        }
        if displaySleepAssertionID != IOPMAssertionID(kIOPMNullAssertionID) {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
        }
        isKeepAwakeActive = false
    }

    private func invalidateTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    // MARK: - Clamshell (privileged pmset)

    /// Enable or disable lid-closed operation.
    ///
    /// `pmset -a disablesleep 1` sets the hidden `SleepDisabled` power setting so
    /// the Mac keeps running when the lid is closed (as long as it's on AC power
    /// and, on many models, an external display is attached). This requires root,
    /// so we run it through `osascript ... with administrator privileges`, which
    /// presents the standard macOS admin authentication dialog.
    ///
    /// When enabling, `duration` optionally schedules an automatic revert:
    ///   - `.indefinite` / `nil`  => stays on until turned off or Quit.
    ///   - `.minutes(m)`          => auto-reverts after `m` minutes.
    ///
    /// The completion handler is always invoked on the main actor.
    func setClamshell(_ enabled: Bool,
                      duration: KeepAwakeDuration? = nil,
                      completion: @escaping @MainActor (ClamshellResult) -> Void) {
        let value = enabled ? "1" : "0"
        // `-a` applies to all power sources. Adjust to `-c` (charger) if you only
        // want it while plugged in.
        let shellCommand = "/usr/bin/pmset -a disablesleep \(value)"

        runWithAdminPrivileges(shellCommand) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.isClamshellActive = enabled
                self.log.info("disablesleep set to \(value, privacy: .public)")
                if enabled {
                    self.scheduleClamshellAutoRevert(duration: duration)
                } else {
                    self.clearClamshellTimer()
                }
                completion(.success)
            case .cancelled:
                // Leave state untouched; re-sync from the system to be safe.
                self.refreshClamshellStateFromSystem()
                completion(.cancelled)
            case .failed(let message):
                self.refreshClamshellStateFromSystem()
                completion(.failed(message))
            }
            self.notifyChange()
        }
    }

    /// Remaining seconds until clamshell auto-reverts, or nil if indefinite / off.
    var clamshellRemainingSeconds: TimeInterval? {
        guard let end = clamshellTimerEndDate else { return nil }
        return max(0, end.timeIntervalSinceNow)
    }

    /// (Re)configure the clamshell auto-revert timer after a successful enable.
    private func scheduleClamshellAutoRevert(duration: KeepAwakeDuration?) {
        clearClamshellTimer()
        switch duration {
        case .none, .some(.indefinite):
            activeClamshellDuration = .indefinite
        case .some(.minutes(let minutes)):
            let interval = TimeInterval(minutes * 60)
            clamshellTimerEndDate = Date().addingTimeInterval(interval)
            activeClamshellDuration = .minutes(minutes)
            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.clamshellTimerDidExpire() }
            }
            RunLoop.main.add(timer, forMode: .common)
            clamshellExpiryTimer = timer
        }
    }

    private func clearClamshellTimer() {
        clamshellExpiryTimer?.invalidate()
        clamshellExpiryTimer = nil
        clamshellTimerEndDate = nil
        activeClamshellDuration = nil
    }

    private func clamshellTimerDidExpire() {
        log.info("Clamshell auto-revert timer expired; resetting disablesleep.")
        // NOTE: reverting needs root, so this will present an admin prompt. If the
        // Mac is unattended (or lid-closed with no external display), the prompt
        // may go unanswered until someone returns — clamshell stays on until then.
        setClamshell(false) { _ in }
    }

    /// Read the real `SleepDisabled` value from `pmset -g` (no privileges needed)
    /// so the UI reflects the actual system state on launch and after changes.
    func refreshClamshellStateFromSystem() {
        DispatchQueue.global(qos: .userInitiated).async {
            let (_, stdout, _) = Self.runProcess("/usr/bin/pmset", ["-g"])
            // Output contains a line like: " SleepDisabled        1"
            var disabled = false
            for line in stdout.split(separator: "\n") where line.contains("SleepDisabled") {
                disabled = line.contains("1")
            }
            DispatchQueue.main.async {
                self.isClamshellActive = disabled
                // On the very first read after launch, a "1" means clamshell was
                // left over from a previous session/crash (we haven't set it yet).
                let isFirstSync = !self.didInitialSync
                self.didInitialSync = true
                self.notifyChange()
                if isFirstSync && disabled {
                    self.onLeftoverClamshellDetected?()
                }
            }
        }
    }

    // MARK: - Cleanup

    /// Called on quit / termination / system sleep. Releases assertions and,
    /// if we turned clamshell mode on, attempts to reset `disablesleep` to 0.
    ///
    /// `resetClamshell` requires an admin prompt, so on abrupt termination we may
    /// only be able to release the (userland) IOKit assertions synchronously.
    func cleanupForQuit(resetClamshell: Bool, completion: @escaping @MainActor () -> Void) {
        releaseAssertions()
        invalidateTimer()
        timerEndDate = nil
        activeDuration = nil
        clearClamshellTimer()

        if resetClamshell && isClamshellActive {
            setClamshell(false) { _ in completion() }
        } else {
            completion()
        }
    }

    // MARK: - Helpers

    private func notifyChange() {
        onChange?()
    }

    // MARK: - Shell execution

    /// Run a command with administrator privileges via osascript's
    /// "do shell script ... with administrator privileges". The auth dialog is
    /// presented by the system; the whole call is done off the main thread and
    /// the result delivered back on the main actor.
    private func runWithAdminPrivileges(_ shellCommand: String,
                                        completion: @escaping @MainActor (ClamshellResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Escape embedded double quotes/backslashes for the AppleScript string literal.
            let escaped = shellCommand
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let appleScript = "do shell script \"\(escaped)\" with administrator privileges"

            let (status, _, stderr) = Self.runProcess("/usr/bin/osascript", ["-e", appleScript])

            let result: ClamshellResult
            if status == 0 {
                result = .success
            } else if stderr.contains("User canceled") || stderr.contains("-128") {
                // osascript reports a cancelled auth dialog as error -128.
                result = .cancelled
            } else {
                result = .failed(stderr.isEmpty ? "Command failed (status \(status))" : stderr)
            }

            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Launch a process synchronously and capture (exitCode, stdout, stderr).
    /// This is `nonisolated static` so it can safely run on a background queue.
    nonisolated static func runProcess(_ launchPath: String, _ arguments: [String]) -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return (-1, "", "Failed to launch \(launchPath): \(error.localizedDescription)")
        }

        // Read before waiting to avoid deadlock on large output (fine for pmset).
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
