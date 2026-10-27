import AppKit
import SwiftUI

@main
struct KomariBarApp: App {
    @StateObject private var model: AppState
    @NSApplicationDelegateAdaptor(KomariBarDelegate.self) private var delegate

    init() {
        let state = AppState()
        _model = StateObject(wrappedValue: state)
        KomariBarDelegate.model = state
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(model: model, openSettings: { AppWindows.shared.showSettings(model: model) })
        } label: {
            Image(systemName: "server.rack")
            Text(model.menuBarText)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class KomariBarDelegate: NSObject, NSApplicationDelegate {
    static var model: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let model = Self.model else { return }
        model.startPolling()
        if CommandLine.arguments.contains("--window") {
            AppWindows.shared.showDashboard(model: model)
        }
    }
}

@MainActor
final class AppWindows {
    static let shared = AppWindows()
    private var settingsWindow: NSWindow?
    private var dashboardWindow: NSWindow?

    func showSettings(model: AppState) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "KomariBar 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showDashboard(model: AppState) {
        if dashboardWindow == nil {
            let root = DashboardView(model: model, openSettings: { self.showSettings(model: model) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "KomariBar · 开发预览"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            dashboardWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }
}
