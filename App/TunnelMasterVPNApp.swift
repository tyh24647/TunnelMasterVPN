import SwiftUI

@main
@MainActor
struct TunnelMasterVPNApp: App {
    @StateObject private var preferences: PreferencesStore
    @StateObject private var service: ServiceClient
    @StateObject private var purchases: PurchaseStore
    @StateObject private var log: EventLog
    @StateObject private var vpn: VPNController

    init() {
        let service = ServiceClient()
        let log = EventLog()
        _preferences = StateObject(wrappedValue: PreferencesStore())
        _service = StateObject(wrappedValue: service)
        _purchases = StateObject(wrappedValue: PurchaseStore(service: service))
        _log = StateObject(wrappedValue: log)
        _vpn = StateObject(wrappedValue: VPNController(log: log))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(preferences)
                .environmentObject(service)
                .environmentObject(purchases)
                .environmentObject(log)
                .environmentObject(vpn)
                .tint(preferences.accent)
                .preferredColorScheme(preferences.scheme)
                .task {
                    await service.refresh()
                    preferences.accountChanged(signedIn: service.account != nil)
                    log.verbose = preferences.value.verbose
                }
                .onChange(of: service.account?.id) { _, id in
                    preferences.accountChanged(signedIn: id != nil)
                }
                .onChange(of: preferences.value.verbose) { _, value in
                    log.verbose = value
                }
        }
    }
}
