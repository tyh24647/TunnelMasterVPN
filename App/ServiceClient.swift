import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import Security
import UIKit

/// HTTPS control-plane client. This app contains no OAuth client secrets or server signing keys.
@MainActor
final class ServiceClient: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var account: Account?
    @Published var servers = ServerLocation.preview
    @Published var catalogIsLive = false
    @Published var purchasesEnabled = false
    @Published var message = "Service is not configured. Personal VPN profiles work independently."
    private var authSession: ASWebAuthenticationSession?
    private var token: String? {
        Keychain.read("session").flatMap { String(data: $0, encoding: .utf8) }
    }

    var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ServiceBaseURL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil else {
            return nil
        }
        return url
    }

    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: String]? = nil) async throws -> T {
        guard let baseURL else {
            throw ServiceError(message: "Configure the HTTPS account/VPN service in Configuration/Developer.xcconfig first.")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError(message: "Service request failed (\(code)). No changes were confirmed.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    func refresh() async {
        guard baseURL != nil else {
            return
        }
        do {
            let response: Catalog = try await request("v1/servers")
            servers = response.servers
            catalogIsLive = true
            purchasesEnabled = response.purchasesEnabled ?? false
            message = "Server catalog updated"
            if token != nil {
                account = try await request("v1/me")
            }
        } catch {
            message = error.localizedDescription
            catalogIsLive = false
            purchasesEnabled = false
        }
    }

    func signIn(provider: String) async throws {
        guard let baseURL else {
            throw ServiceError(message: "Account service has not been configured.")
        }
        let state = try randomToken()
        let verifier = try randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var parts = URLComponents(url: baseURL.appendingPathComponent("v1/auth/authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "redirect_uri", value: "tunneldojo://auth/callback")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: parts.url!, callbackURLScheme: "tunneldojo") { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? ServiceError(message: "Sign-in cancelled."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            authSession = session
            if !session.start() {
                continuation.resume(throwing: ServiceError(message: "Unable to open secure sign-in."))
            }
        }
        guard callback.host == "auth", callback.path == "/callback",
              let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              query.first(where: { $0.name == "state" })?.value == state,
              let code = query.first(where: { $0.name == "code" })?.value else {
            throw ServiceError(message: "Sign-in callback could not be verified.")
        }
        let session: Session = try await request("v1/auth/exchange", method: "POST", body: [
            "code": code, "code_verifier": verifier, "redirect_uri": "tunneldojo://auth/callback"
        ])
        try Keychain.save(Data(session.token.utf8), key: "session")
        account = session.account
        authSession = nil
    }

    func emailLink(_ email: String) async throws {
        let reply: ServiceReply = try await request("v1/auth/email", method: "POST", body: ["email": email])
        message = reply.message
    }

    func confirmEmail(code: String) async throws {
        let session: Session = try await request("v1/auth/email/confirm", method: "POST", body: ["code": code])
        try Keychain.save(Data(session.token.utf8), key: "session")
        account = session.account
    }

    func registerDevice() async throws {
        var id = Keychain.read("deviceID").flatMap { String(data: $0, encoding: .utf8) }
        if id == nil {
            id = UUID().uuidString
            try Keychain.save(Data(id!.utf8), key: "deviceID")
        }
        let reply: ServiceReply = try await request("v1/devices", method: "POST", body: ["deviceID": id!, "name": UIDevice.current.model])
        message = reply.message
    }

    func redeemReferral(_ code: String) async throws {
        let reply: ServiceReply = try await request("v1/referrals/redeem", method: "POST", body: ["code": code])
        message = reply.message
    }

    func startLifetimeTrial() async throws {
        let reply: ServiceReply = try await request("v1/trials/lifetime", method: "POST", body: [:])
        message = reply.message
        await refresh()
    }

    func inviteFamily(_ emails: String) async throws {
        let reply: ServiceReply = try await request("v1/family/invitations", method: "POST", body: ["emails": emails])
        message = reply.message
    }

    func provision(server: ServerLocation, exit: String?) async throws -> ProvisionedProfile {
        try await request("v1/tunnels", method: "POST", body: ["serverID": server.id, "exitID": exit ?? "", "deviceID": Keychain.read("deviceID").flatMap { String(data: $0, encoding: .utf8) } ?? ""])
    }

    func deleteAccount() async throws {
        let _: ServiceReply = try await request("v1/me", method: "DELETE")
        signOut()
    }

    func signOut() {
        Keychain.remove("session")
        account = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ServiceError(message: "Secure random generator unavailable.")
        }
        return Data(bytes).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct Catalog: Codable {
    var servers: [ServerLocation]
    var purchasesEnabled: Bool?
}

struct ServiceReply: Codable {
    var message: String
}

struct ProvisionedProfile: Codable {
    var profile: VPNProfile
    var password: String
    var psk: String?
}
