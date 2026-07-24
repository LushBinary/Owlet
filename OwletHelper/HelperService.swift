//
//  HelperService.swift
//  OwletHelper
//
//  The root-privileged implementation of `OwletHelperProtocol`. Because the
//  daemon already runs as root, it can call `pmset` directly with no admin
//  prompt — which is the whole reason the helper exists (unattended, timed, and
//  battery-triggered clamshell reverts).
//

import Foundation

final class HelperService: NSObject, OwletHelperProtocol {

    func getVersion(reply: @escaping (Int) -> Void) {
        reply(OwletHelper.currentVersion)
    }

    func setClamshell(_ enabled: Bool, reply: @escaping (Bool, String) -> Void) {
        let value = enabled ? "1" : "0"
        let (status, stderr) = Self.runPmset(disablesleep: value)
        if status == 0 {
            reply(true, "")
        } else {
            reply(false, stderr.isEmpty ? "pmset exited with status \(status)" : stderr)
        }
    }

    /// Run `/usr/bin/pmset -a disablesleep <value>` as root and return (exit, stderr).
    private static func runPmset(disablesleep value: String) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", value]

        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return (-1, "Failed to launch pmset: \(error.localizedDescription)")
        }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stderr)
    }
}
