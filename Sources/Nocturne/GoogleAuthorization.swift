import AppKit
import CryptoKit
import Network
import Security

struct DesktopClient: Codable {
  let client_id: String
  let client_secret: String?
  static func read(_ url: URL) throws -> Self {
    struct File: Decodable { let installed: DesktopClient }
    let client = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).installed
    guard client.client_id.hasSuffix(".apps.googleusercontent.com") else {
      throw Issue("Choose a Google Desktop app OAuth client JSON file.")
    }
    return client
  }
}
struct GoogleGrant: Codable {
  let client: DesktopClient
  let refresh: String
}
enum GrantStore {
  static let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "studio.nocturne.player.google",
    kSecAttrAccount as String: "youtube.readonly",
  ]
  static func read() throws -> GoogleGrant? {
    var q = query
    q[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw Issue("Keychain could not open the Google connection.")
    }
    return try JSONDecoder().decode(GoogleGrant.self, from: data)
  }
  static func save(_ grant: GoogleGrant) throws {
    let data = try JSONEncoder().encode(grant)
    let attrs = [kSecValueData as String: data] as CFDictionary
    let updated = SecItemUpdate(query as CFDictionary, attrs)
    if updated == errSecSuccess { return }
    var entry = query
    entry[kSecValueData as String] = data
    entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    guard updated == errSecItemNotFound, SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
    else { throw Issue("Keychain could not save this Google connection.") }
  }
  static func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Issue("Keychain could not remove this connection.")
    }
  }
}
enum GoogleOAuth {
  static let scope = "https://www.googleapis.com/auth/youtube.readonly"
  struct Tokens: Decodable {
    let access_token: String
    let refresh_token: String?
  }
  static func random() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw Issue("Could not start a secure sign-in.")
    }
    return encoded(Data(bytes))
  }
  static func encoded(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
      of: "/", with: "_"
    ).replacingOccurrences(of: "=", with: "")
  }
  static func consent(_ client: DesktopClient, redirect: String, state: String, verifier: String)
    -> URL
  {
    URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!.appending(queryItems: [
      .init(name: "client_id", value: client.client_id),
      .init(name: "redirect_uri", value: redirect),
      .init(name: "response_type", value: "code"), .init(name: "scope", value: scope),
      .init(name: "state", value: state),
      .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
      .init(name: "code_challenge_method", value: "S256"),
      .init(name: "code_challenge", value: encoded(Data(SHA256.hash(data: Data(verifier.utf8))))),
    ])
  }
  static func tokens(_ client: DesktopClient, fields: [String: String]) async throws -> Tokens {
    var params = fields
    params["client_id"] = client.client_id
    params["client_secret"] = client.client_secret
    let safe = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    var req = URLRequest(
      url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 20)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = Data(
      params.map {
        ($0.key.addingPercentEncoding(withAllowedCharacters: safe) ?? "") + "="
          + ($0.value.addingPercentEncoding(withAllowedCharacters: safe) ?? "")
      }.joined(separator: "&").utf8)
    let (data, response) = try await URLSession.shared.data(for: req)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      struct Failure: Decodable { let error: String }
      let reason = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "request failed"
      throw Issue("Google authorization: " + reason + ". Reconnect if access has expired.")
    }
    return try JSONDecoder().decode(Tokens.self, from: data)
  }
}
/// Receives one consent response on an ephemeral IPv4 loopback port.
@MainActor final class ConsentReceiver {
  private var listener: NWListener?
  private var waiting: CheckedContinuation<(String, String), Error>?
  private var timeout: Task<Void, Never>?
  private var redirect = ""
  private var state = ""
  func authorize(client: DesktopClient, verifier: String) async throws -> (String, String) {
    state = try GoogleOAuth.random()
    let params = NWParameters.tcp
    params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: params)
    self.listener = listener
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiting = continuation
        if Task.isCancelled {
          finish(.failure(CancellationError()))
          return
        }
        listener.stateUpdateHandler = { [weak self, weak listener] status in
          Task { @MainActor in
            guard let self, self.waiting != nil else { return }
            switch status {
            case .ready:
              guard let port = listener?.port else {
                self.finish(.failure(Issue("Google callback port unavailable.")))
                return
              }
              self.redirect = "http://127.0.0.1:" + String(port.rawValue) + "/oauth2callback"
              if !NSWorkspace.shared.open(
                GoogleOAuth.consent(
                  client, redirect: self.redirect, state: self.state, verifier: verifier))
              {
                self.finish(.failure(Issue("Could not open Google sign-in.")))
              }
            case .failed(let error): self.finish(.failure(error))
            default: break
            }
          }
        }
        listener.newConnectionHandler = { [weak self] connection in
          Task { @MainActor in self?.receive(connection) }
        }
        listener.start(queue: .main)
        timeout = Task {
          try? await Task.sleep(for: .seconds(180))
          if !Task.isCancelled { finish(.failure(Issue("Google sign-in timed out."))) }
        }
      }
    } onCancel: {
      Task { @MainActor in self.finish(.failure(CancellationError())) }
    }
  }
  private func receive(_ connection: NWConnection) {
    connection.start(queue: .main)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
      [weak self] data, _, _, _ in
      Task { @MainActor in
        guard let self, let data,
          let line = String(data: data, encoding: .utf8)?.components(separatedBy: "\r\n").first
        else {
          connection.cancel()
          return
        }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", let u = URLComponents(string: String(parts[1])),
          u.path == "/oauth2callback",
          u.queryItems?.first(where: { $0.name == "state" })?.value == self.state,
          self.waiting != nil
        else {
          connection.cancel()
          return
        }
        let code = u.queryItems?.first(where: { $0.name == "code" })?.value
        let message =
          code == nil
          ? "Sign-in cancelled. Return to NOCTURNE." : "Return to NOCTURNE to finish connecting."
        let reply =
          "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "
          + String(message.utf8.count) + "\r\n\r\n" + message
        connection.send(
          content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
        if let code {
          self.finish(.success((code, self.redirect)))
        } else {
          self.finish(.failure(Issue("Google sign-in was cancelled.")))
        }
      }
    }
  }
  private func finish(_ result: Result<(String, String), Error>) {
    listener?.cancel()
    listener = nil
    timeout?.cancel()
    timeout = nil
    let pending = waiting
    waiting = nil
    pending?.resume(with: result)
  }
}
