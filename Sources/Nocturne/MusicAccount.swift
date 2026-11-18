import CryptoKit
import SwiftUI
import WebKit

/// Account pairing without the Data API: the user signs in to YouTube Music once in an in-app
/// window, and library requests then carry that session the same way music.youtube.com does.
extension MusicBrowse {
  static var credentials: (cookie: String, sapisid: String)?
  static func authorization(sapisid: String, time: Int) -> String {
    let digest = Insecure.SHA1.hash(
      data: Data("\(time) \(sapisid) https://music.youtube.com".utf8))
    return "SAPISIDHASH \(time)_" + digest.map { String(format: "%02x", $0) }.joined()
  }
  /// Reads the signed-in session from WebKit's cookie store; false when there is none.
  @MainActor static func loadCredentials() async -> Bool {
    let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies().filter {
      $0.domain.hasSuffix("youtube.com")
    }
    guard
      let sapisid = cookies.first(where: { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" })?
        .value, let header = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    else {
      credentials = nil
      return false
    }
    credentials = (header, sapisid)
    return true
  }
  @MainActor static func signOut() {
    credentials = nil
    WKWebsiteDataStore.default().removeData(
      ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast) {}
  }
  /// Every playlist in the signed-in library (including Liked Music) with its tracks.
  static func accountLists() async throws -> [AccountList] {
    let links = try await load("FEmusic_liked_playlists").sections.flatMap(\.links).filter {
      $0.id.hasPrefix("VL")
    }
    guard !links.isEmpty else {
      throw Issue("No playlists were found in this YouTube Music account. Sign in again if the session expired.")
    }
    var lists: [AccountList] = []
    for link in links {
      let tracks = (try? await load(link.id))?.tracks ?? []
      try Task.checkCancellation()
      lists.append(AccountList(id: link.id, name: link.title, tracks: tracks))
    }
    return lists
  }
}

@MainActor final class MusicSignIn: NSObject, WKNavigationDelegate, NSWindowDelegate {
  private var window: NSWindow?
  private var done: ((Bool) -> Void)?
  func start(_ done: @escaping (Bool) -> Void) {
    finish(false)
    self.done = done
    let config = WKWebViewConfiguration()
    // Same Safari compatibility token as the catalog view; Google refuses unknown embedded browsers.
    if let version = Bundle(path: "/Applications/Safari.app")?.object(
      forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    {
      config.applicationNameForUserAgent = "Version/" + version + " Safari/605.1.15"
    }
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: config)
    web.navigationDelegate = self
    let panel = NSWindow(
      contentRect: web.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered,
      defer: false)
    panel.title = L("Sign in to YouTube Music")
    panel.contentView = web
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    window = panel
    web.load(
      URLRequest(
        url: URL(
          string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com%2F")!))
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard webView.url?.host == "music.youtube.com" else { return }
    Task { if await MusicBrowse.loadCredentials() { finish(true) } }
  }
  func windowWillClose(_ notification: Notification) { finish(false) }
  private func finish(_ ok: Bool) {
    guard let done else { return }
    self.done = nil
    window?.delegate = nil
    window?.close()
    window = nil
    done(ok)
  }
}
