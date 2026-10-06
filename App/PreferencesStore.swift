import SwiftUI

/// A small, versioned preference document; credentials and diagnostic logs never sync.
@MainActor
final class PreferencesStore: ObservableObject {
    @Published var value: Preferences
    @Published var syncMessage = "Device only"
    private let key = "TunnelDojo.preferences.v1"
    private var observer: NSObjectProtocol?
    private var canSync = false

    init() {
        value = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.mergeCloud()
            }
        }
    }

    var accent: Color {
        Color(red: value.accentRed, green: value.accentGreen, blue: value.accentBlue)
    }

    var scheme: ColorScheme? {
        switch value.theme {
        case "Light":
            return .light
        case "Dark":
            return .dark
        default:
            return nil
        }
    }

    func accountChanged(signedIn: Bool) {
        canSync = signedIn
        if signedIn && value.cloudSync {
            NSUbiquitousKeyValueStore.default.synchronize()
            mergeCloud()
        }
        syncMessage = signedIn && value.cloudSync ? "iCloud settings enabled" : "Device only"
    }

    func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { self.value[keyPath: path] }, set: {
            self.value[keyPath: path] = $0
            self.save()
        })
    }

    func save() {
        value.modified = Date()
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
        if canSync && value.cloudSync {
            guard data.count < 800_000 else {
                syncMessage = "Settings exceed iCloud's size budget; saved on this device."
                return
            }
            NSUbiquitousKeyValueStore.default.set(data, forKey: key)
            NSUbiquitousKeyValueStore.default.synchronize()
            syncMessage = "Settings submitted to iCloud"
        } else {
            syncMessage = "Device only"
        }
    }

    private func mergeCloud() {
        guard canSync, value.cloudSync,
              let data = NSUbiquitousKeyValueStore.default.data(forKey: key),
              let remote = try? JSONDecoder().decode(Preferences.self, from: data),
              remote.modified > value.modified else {
            return
        }
        value = remote
        UserDefaults.standard.set(data, forKey: key)
        syncMessage = "Settings received from iCloud"
    }
}
