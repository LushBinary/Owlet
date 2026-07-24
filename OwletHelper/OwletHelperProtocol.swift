//
//  OwletHelperProtocol.swift
//  Owlet + OwletHelper (shared)
//
//  The XPC contract between the Owlet app and its privileged helper daemon.
//  Compiled into BOTH the app target (the client) and the helper target (the
//  server). Keep it dependency-free so it builds in a plain command-line tool.
//

import Foundation

/// Well-known identifiers shared by the app and the helper.
enum OwletHelper {
    /// launchd label for the daemon. Must match the embedded launchd plist's
    /// `Label` and the plist filename registered with SMAppService.
    static let machServiceName = "com.lushbinary.Owlet.Helper"

    /// The plist filename (under Contents/Library/LaunchDaemons) passed to
    /// `SMAppService.daemon(plistName:)`.
    static let plistName = "com.lushbinary.Owlet.Helper.plist"

    /// Bumped whenever the protocol changes so the app can detect a stale helper
    /// and re-install it.
    static let currentVersion = 1
}

/// Methods the privileged (root) helper exposes to the app over XPC.
///
/// The whole point of the helper is to flip the system-wide `SleepDisabled`
/// power setting (clamshell mode) *without* an admin prompt, so timed and
/// battery-triggered auto-reverts work while the Mac is unattended.
@objc protocol OwletHelperProtocol {

    /// Report the helper's protocol version so the app can detect an outdated
    /// helper binary and re-register a newer one.
    func getVersion(reply: @escaping (Int) -> Void)

    /// Set the hidden `disablesleep` power setting (clamshell mode).
    /// - Parameters:
    ///   - enabled: `true` runs `pmset -a disablesleep 1`, `false` runs `... 0`.
    ///   - reply: `success` is true on a clean exit; `message` carries any error.
    func setClamshell(_ enabled: Bool, reply: @escaping (_ success: Bool, _ message: String) -> Void)
}
