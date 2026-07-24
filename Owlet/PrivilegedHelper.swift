//
//  PrivilegedHelper.swift
//  Owlet
//
//  App-side wrapper around the privileged helper daemon (see the OwletHelper
//  target). Registers/unregisters the daemon via SMAppService (macOS 13+) and
//  talks to it over XPC to flip clamshell mode *without* an admin prompt.
//
//  This is what makes unattended and battery-triggered clamshell reverts work:
//  when the helper is installed, PowerManager routes pmset through it; otherwise
//  it falls back to the osascript admin-prompt path.
//
//  IMPORTANT: SMAppService only runs daemons from a Developer ID-signed app. In
//  an unsigned / ad-hoc build `register()` fails and Owlet transparently falls
//  back to the admin-prompt behavior.
//

import Foundation
import ServiceManagement
import os

/// One-shot guard so an XPC continuation is only ever resumed once, even if both
/// the reply and the error handler fire.
private final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

@MainActor
enum PrivilegedHelper {

    private static let log = Logger(subsystem: "com.lushbinary.Owlet", category: "PrivilegedHelper")

    private static var service: SMAppService {
        SMAppService.daemon(plistName: OwletHelper.plistName)
    }

    /// Current registration status of the daemon.
    static var status: SMAppService.Status { service.status }

    /// True when the daemon is registered and enabled (ready to serve XPC).
    static var isEnabled: Bool { service.status == .enabled }

    /// True when macOS is waiting for the user to approve the daemon under
    /// System Settings > General > Login Items.
    static var requiresApproval: Bool { service.status == .requiresApproval }

    /// Register (install) the daemon. Returns nil on success or an error message.
    /// Fails on unsigned/ad-hoc builds — callers should treat that as "no helper".
    @discardableResult
    static func register() -> String? {
        do {
            try service.register()
            log.info("Helper registered; status=\(String(describing: service.status), privacy: .public)")
            return nil
        } catch {
            log.error("Helper register failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    /// Unregister (remove) the daemon. Returns nil on success or an error message.
    @discardableResult
    static func unregister() -> String? {
        do {
            try service.unregister()
            return nil
        } catch {
            log.error("Helper unregister failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    /// Ask the helper to set clamshell mode. Returns `nil` when the helper isn't
    /// available, so the caller can fall back to the admin-prompt path. When the
    /// helper is present, returns its `.success` / `.failed` result (no prompt).
    static func setClamshell(_ enabled: Bool) async -> ClamshellResult? {
        guard isEnabled else { return nil }

        let connection = NSXPCConnection(machServiceName: OwletHelper.machServiceName,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: OwletHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        let once = OnceFlag()
        return await withCheckedContinuation { (continuation: CheckedContinuation<ClamshellResult, Never>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                if once.claim() {
                    continuation.resume(returning: .failed("Helper connection error: \(error.localizedDescription)"))
                }
            } as? OwletHelperProtocol

            guard let proxy else {
                if once.claim() { continuation.resume(returning: .failed("Helper proxy unavailable")) }
                return
            }

            proxy.setClamshell(enabled) { success, message in
                if once.claim() {
                    continuation.resume(returning: success ? .success : .failed(message))
                }
            }
        }
    }
}
