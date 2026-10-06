import Foundation
import Darwin

/// Allow rules take precedence. A regex budget error blocks the query rather than bypassing a rule.
enum DNSMatcher {
    static var regexAvailable: Bool {
        td_regex_available() == 1
    }

    static func isIPv4(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    static func validate(_ rules: [DNSRule]) throws {
        guard rules.count <= 2000 else {
            throw ServiceError(message: "Use at most 2,000 local rules.")
        }
        for rule in rules where rule.enabled {
            guard !rule.pattern.isEmpty, rule.pattern.utf8.count <= 4096 else {
                throw ServiceError(message: "A rule is empty or longer than 4,096 bytes.")
            }
            _ = try matches(rule, hostname: "validation.invalid")
        }
    }

    static func blocked(_ hostname: String, rules: [DNSRule]) throws -> Bool {
        for rule in rules where rule.enabled && rule.allow {
            if try matches(rule, hostname: hostname) {
                return false
            }
        }
        for rule in rules where rule.enabled && !rule.allow {
            if try matches(rule, hostname: hostname) {
                return true
            }
        }
        return false
    }

    static func matches(_ rule: DNSRule, hostname: String) throws -> Bool {
        let host = hostname.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let pattern = rule.pattern.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch rule.kind {
        case .hostname:
            return host == pattern || host.hasSuffix("." + pattern)
        case .wildcard:
            // A bounded dynamic-programming glob matcher: '*' = any sequence, '?' = one character.
            let chars = Array(host)
            var previous = [Bool](repeating: false, count: chars.count + 1)
            previous[0] = true
            for char in pattern {
                var next = [Bool](repeating: false, count: chars.count + 1)
                next[0] = char == "*" && previous[0]
                for index in 0..<chars.count {
                    if char == "*" {
                        next[index + 1] = previous[index + 1] || next[index]
                    } else {
                        next[index + 1] = previous[index] && (char == "?" || char == chars[index])
                    }
                }
                previous = next
            }
            return previous[chars.count]
        case .regex:
            var buffer = [CChar](repeating: 0, count: 256)
            let result = td_regex_match(rule.pattern, host, &buffer, buffer.count)
            guard result >= 0 else {
                throw ServiceError(message: String(cString: buffer))
            }
            return result == 1
        }
    }
}
