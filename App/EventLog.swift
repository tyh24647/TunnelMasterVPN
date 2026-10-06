import Foundation
import Combine

struct LogEvent: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var level: String
    var message: String
}

/// Logs only predefined operational events. Never pass credentials, URLs or DNS queries here.
@MainActor
final class EventLog: ObservableObject {
    @Published private(set) var events: [LogEvent] = []
    var verbose = false

    func add(_ message: String, level: String = "Info") {
        if level == "Debug" && !verbose {
            return
        }
        events.append(LogEvent(level: level, message: message))
        if events.count > 1000 {
            events.removeFirst(events.count - 1000)
        }
    }

    func filtered(_ filter: String) -> [LogEvent] {
        events.filter { event in
            switch filter {
            case "Errors":
                return event.level == "Error"
            case "Warnings & errors":
                return event.level == "Error" || event.level == "Warning"
            default:
                return true
            }
        }
    }

    func export(_ filter: String) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let text = filtered(filter).map {
            "\(formatter.string(from: $0.date)) [\($0.level)] \($0.message)"
        }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TunnelMasterVPN-events.txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        return url
    }

    func clear() {
        events.removeAll()
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("TunnelMasterVPN-events.txt"))
    }
}
