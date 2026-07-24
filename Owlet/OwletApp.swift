//
//  OwletApp.swift
//  Owlet
//
//  Owlet is a menu-bar-only (LSUIElement) app, so there is no WindowGroup. The
//  SwiftUI App exists purely to host the AppDelegate via the delegate adaptor;
//  all UI lives in the status bar. The empty `Settings` scene means the app has
//  no main window and never opens one on launch.
//

import SwiftUI

@main
struct OwletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
