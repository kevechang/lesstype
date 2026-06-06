import SwiftUI

struct MainWindowView: View {
    let store: PreferencesStore
    let runtimeStatus: RuntimeStatus
    let sessionHistoryStore: SessionHistoryStore
    let retryHotkeys: () -> Void

    var body: some View {
        SettingsView(
            store: store,
            runtimeStatus: runtimeStatus,
            sessionHistoryStore: sessionHistoryStore,
            retryHotkeys: retryHotkeys
        )
        .frame(minWidth: 820, minHeight: 620)
    }
}
