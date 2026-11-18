import SwiftUI

@MainActor final class AccountSync: ObservableObject {
  weak var session: Session?
  @Published private(set) var connected = false
  @Published private(set) var busy = false
  @Published var notice: String?
  private var grant: GoogleGrant?
  private var cached: (value: String, expires: Date)?
  private var work: Task<Void, Never>?
  private var schedule: Task<Void, Never>?
  private var generation = UUID()
  static var bundled: URL? { Bundle.main.url(forResource: "GoogleOAuth", withExtension: "json") }
  func restore(_ session: Session) {
    self.session = session
    if UserDefaults.standard.bool(forKey: "music.signedIn") {
      Task {
        if await MusicBrowse.loadCredentials() {
          connected = true
          startSchedule()
          sync()
        } else {
          notice = L("Your YouTube Music session expired. Sign in again.")
        }
      }
      return
    }
    guard UserDefaults.standard.bool(forKey: "google.connected") else { return }
    do {
      grant = try GrantStore.read()
      connected = grant != nil
      if connected {
        startSchedule()
        sync()
      }
    } catch { notice = error.localizedDescription }
  }
  private let signIn = MusicSignIn()
  func signInToMusic() {
    guard !busy else { return }
    signIn.start { [weak self] ok in
      guard let self, ok else { return }
      UserDefaults.standard.set(true, forKey: "music.signedIn")
      notice = nil
      connected = true
      startSchedule()
      sync()
    }
  }
  func connect() {
    guard !busy else { return }
    let source: URL
    if let url = Self.bundled {
      source = url
    } else {
      let panel = NSOpenPanel()
      panel.title = L("Select Google Desktop OAuth client JSON")
      panel.allowedContentTypes = [.json]
      guard panel.runModal() == .OK, let url = panel.url else { return }
      source = url
    }
    busy = true
    notice = L("Waiting for Google authorization…")
    work = Task {
      defer { busy = false }
      do {
        let client = try DesktopClient.read(source)
        let verifier = try GoogleOAuth.random()
        let (code, redirect) = try await ConsentReceiver().authorize(
          client: client, verifier: verifier)
        let token = try await GoogleOAuth.tokens(
          client,
          fields: [
            "grant_type": "authorization_code", "code": code, "redirect_uri": redirect,
            "code_verifier": verifier,
          ])
        try Task.checkCancellation()
        guard let refresh = token.refresh_token else {
          throw Issue("Google did not grant offline access. Reconnect to authorize automatic sync.")
        }
        let value = GoogleGrant(client: client, refresh: refresh)
        try GrantStore.save(value)
        grant = value
        cached = (token.access_token, Date().addingTimeInterval(3000))
        connected = true
        UserDefaults.standard.set(true, forKey: "google.connected")
        startSchedule()
        try await pull()
      } catch { if !Task.isCancelled { notice = error.localizedDescription } }
    }
  }
  private func startSchedule() {
    schedule?.cancel()
    schedule = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1800)) } catch { return }
        self?.sync()
      }
    }
  }
  func sync() {
    guard connected, !busy else { return }
    busy = true
    let id = generation
    work = Task {
      defer { if generation == id { busy = false } }
      do { try await pull() } catch { if !Task.isCancelled { notice = error.localizedDescription } }
    }
  }
  func access() async throws -> String {
    if let cached, cached.expires > Date() { return cached.value }
    guard let grant else { throw Issue("Connect your Google account first.") }
    let id = generation
    let token = try await GoogleOAuth.tokens(
      grant.client, fields: ["grant_type": "refresh_token", "refresh_token": grant.refresh])
    try Task.checkCancellation()
    guard id == generation, connected else { throw CancellationError() }
    cached = (token.access_token, Date().addingTimeInterval(3000))
    return token.access_token
  }
  private func pull() async throws {
    notice = L("Syncing playlists…")
    let id = generation
    let lists =
      MusicBrowse.credentials != nil
      ? try await MusicBrowse.accountLists() : try await GoogleCatalog().playlists(try await access())
    try Task.checkCancellation()
    guard id == generation, let session else { return }
    let now = Date()
    session.change { data in
      data.googleLists = lists
      data.googleSync = now
    }
    notice = session.library.googleSync == now ? nil : L("Could not save the updated playlists.")
  }
  func disconnect() {
    do { try GrantStore.clear() } catch {
      notice = error.localizedDescription
      return
    }
    generation = UUID()
    work?.cancel()
    schedule?.cancel()
    grant = nil
    cached = nil
    connected = false
    busy = false
    notice = nil
    if UserDefaults.standard.bool(forKey: "music.signedIn") { MusicBrowse.signOut() }
    UserDefaults.standard.removeObject(forKey: "music.signedIn")
    UserDefaults.standard.removeObject(forKey: "google.connected")
    session?.change {
      $0.googleLists = nil
      $0.googleSync = nil
    }
  }
  func cancel() {
    work?.cancel()
    notice = nil
  }
}
struct AccountControls: View {
  @ObservedObject var sync: AccountSync
  let last: Date?
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if sync.connected {
        Text("YouTube playlists sync every 30 minutes while NOCTURNE is open.").font(.caption)
        if let last {
          Text(L("Last synced") + " " + last.formatted()).font(.caption).foregroundStyle(.secondary)
        }
        HStack {
          Button("Sync now") { sync.sync() }.disabled(sync.busy)
          Button("Disconnect") { sync.disconnect() }
        }
      } else {
        Text(
          "Sign in once and your YouTube Music playlists are copied into NOCTURNE and kept up to date. No API key is needed."
        ).font(.caption).foregroundStyle(.secondary)
        Button("Sign in to YouTube Music…") { sync.signInToMusic() }.disabled(sync.busy)
        if AccountSync.bundled != nil {
          Button("Connect Google account…") { sync.connect() }.disabled(sync.busy)
        }
      }
      if sync.busy {
        HStack {
          ProgressView().controlSize(.small)
          Button("Cancel") { sync.cancel() }
        }
      }
      if let note = sync.notice { Text(note).font(.caption).textSelection(.enabled) }
    }
  }
}
