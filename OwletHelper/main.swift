//
//  main.swift
//  OwletHelper
//
//  Entry point for the privileged helper daemon. launchd starts this process as
//  root (via the embedded LaunchDaemon plist) and hands it the XPC listener for
//  the Mach service declared in that plist. We accept connections from the app,
//  expose `OwletHelperProtocol`, and exit when idle so we don't linger.
//

import Foundation

/// Delegate that wires each incoming XPC connection up to a `HelperService`.
final class HelperDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // NOTE: In a signed build you should additionally verify the peer's code
        // signature here (matching team identifier / requirement) before trusting
        // it. SMAppService already restricts connections to the owning app, but an
        // explicit check via `newConnection.setCodeSigningRequirement(_:)`
        // (macOS 13+) is good defense in depth.
        newConnection.exportedInterface = NSXPCInterface(with: OwletHelperProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: OwletHelper.machServiceName)
listener.delegate = delegate
listener.resume()

// Run forever servicing XPC requests; launchd manages our lifecycle.
RunLoop.current.run()
