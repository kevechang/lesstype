import SwiftUI

@main
struct VoiceInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("lesstype", id: "main") {
            MainWindowView(
                store: appDelegate.preferencesStore,
                runtimeStatus: appDelegate.runtimeStatus,
                sessionHistoryStore: appDelegate.sessionHistoryStore,
                retryHotkeys: {
                    appDelegate.retryHotkeys()
                }
            )
        }
        .defaultSize(width: 920, height: 680)

        MenuBarExtra("lesstype", systemImage: "waveform") {
            Button("打开主界面") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("打开设置") {
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            }
            Divider()
            Button("退出") {
                NSApp.terminate(nil)
            }
        }

        Settings {
            SettingsView(
                store: appDelegate.preferencesStore,
                runtimeStatus: appDelegate.runtimeStatus,
                sessionHistoryStore: appDelegate.sessionHistoryStore,
                retryHotkeys: {
                    appDelegate.retryHotkeys()
                }
            )
        }
    }
}
