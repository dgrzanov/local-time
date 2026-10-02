import AppKit
import SwiftData
import SwiftUI

@main
struct LocalTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Project.self, TimeEntry.self, AppSettings.self)
        } catch {
            fatalError("Unable to create the local database: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup("Local Time", id: "main") {
            DashboardView()
                .modelContainer(container)
                .frame(minWidth: 1_000, minHeight: 620)
        }
        .defaultSize(width: 1_180, height: 760)

        Settings {
            SettingsView()
                .modelContainer(container)
                .frame(width: 440, height: 390)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Open Local Time")
            button.target = self
            button.action = #selector(openMainWindow)
            button.sendAction(on: [.leftMouseUp])
        }
        statusItem = item
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func openMainWindow() {
        WindowCoordinator.shared.showMainWindow()
    }
}

@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()
    var openWindow: (() -> Void)?

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        openWindow?()
        DispatchQueue.main.async { [weak self] in
            self?.mainWindow()?.makeKeyAndOrderFront(nil)
        }
    }

    private func mainWindow() -> NSWindow? {
        NSApp.windows.first {
            $0.canBecomeMain && !($0 is NSPanel) && $0.title == "Local Time"
        }
    }
}
