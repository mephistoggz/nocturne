import SwiftUI
import WebKit

/// Only the remote catalog is rendered by YouTube. The app owns search input,
/// navigation, saved collections, and the selected track's playback session.
struct OnlineCatalog: View {
  @ObservedObject var s: Session
  let initial: URL
  @StateObject private var page = CatalogPage()
  @FocusState private var focus: Bool
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button {
          page.web.goBack()
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(!page.canGoBack).help("Back")
        Button("Search music") { s.route = .search }
        Spacer()
        if let url = page.url, let kind = YouTubeMusic.pageKind(url) {
          Button(L("Save " + kind.lowercased())) {
            s.savePage(url, name: page.web.title ?? kind, kind: kind)
          }.disabled(
            s.library.pages?.contains(where: {
              YouTubeMusic.canonicalPage($0.url) == YouTubeMusic.canonicalPage(url)
            }) == true)
        }
        Button {
          page.open(page.url ?? initial)
        } label: {
          Image(systemName: "arrow.clockwise")
        }.help("Reload")
      }.padding(10)
      Divider()
      if let message = page.message {
        HStack {
          Text(message)
          Spacer()
          Button("Retry") { page.open(initial) }
        }.padding(10)
      }
      CatalogSurface(page: page)
    }
    .onAppear {
      page.session = s
      page.open(initial)
    }
    .onChange(of: initial) { _, url in page.open(url) }
    .onDisappear { page.deactivate() }
  }
}
@MainActor final class CatalogPage: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
  let web: WKWebView
  weak var session: Session?
  @Published var url: URL?
  @Published var canGoBack = false
  @Published var message: String?
  private var observers: [NSKeyValueObservation] = []
  private var selection: Task<Void, Never>?
  private var selecting: String?
  private var active = false
  private var lastCatalog: URL?
  override init() {
    let config = WKWebViewConfiguration()
    // Publish WebKit's Safari compatibility token alongside our own product name.
    // Anonymous catalog pages otherwise serve a browser-upgrade interstitial.
    if let version = Bundle(path: "/Applications/Safari.app")?.object(
      forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    {
      config.applicationNameForUserAgent = "Version/" + version + " Safari/605.1.15 NOCTURNE/1.1"
    }
    config.mediaTypesRequiringUserActionForPlayback = .all
    web = WKWebView(frame: .zero, configuration: config)
    super.init()
    web.navigationDelegate = self
    web.uiDelegate = self
    web.allowsBackForwardNavigationGestures = true
    observers.append(
      web.observe(\.url, options: [.new]) { [weak self] view, _ in
        let next = view.url
        Task { @MainActor in
          guard let self, self.active, let next, self.web.url == next else { return }
          self.url = next
          if YouTubeMusic.videoID(next) != nil {
            self.choose(next, restore: true)
          } else if next.host == "music.youtube.com" {
            self.lastCatalog = next
          }
        }
      })
    observers.append(
      web.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
        let back = view.canGoBack
        Task { @MainActor in self?.canGoBack = back }
      })
  }
  func open(_ url: URL) {
    active = true
    message = nil
    selection?.cancel()
    selecting = nil
    web.load(URLRequest(url: url, timeoutInterval: 20))
  }
  func deactivate() {
    active = false
    selection?.cancel()
    selecting = nil
    web.stopLoading()
    web.pauseAllMediaPlayback(completionHandler: nil)
  }
  private func choose(_ link: URL, restore: Bool) {
    guard let id = YouTubeMusic.videoID(link), let session, active, selecting != id else { return }
    selecting = id
    selection?.cancel()
    web.pauseAllMediaPlayback(completionHandler: nil)
    if restore, let lastCatalog { web.load(URLRequest(url: lastCatalog)) }
    selection = Task {
      defer { if selecting == id { selecting = nil } }
      do {
        let track: Track
        if let known = session.library.tracks.first(where: { $0.id == id }) {
          track = known
        } else {
          track = try await session.provider.resolve(link)
        }
        try Task.checkCancellation()
        guard active else { return }
        session.change { $0.add(track) }
        session.select(track, in: [track])
      } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard action.targetFrame?.isMainFrame != false, let url = action.request.url else {
      decisionHandler(.allow)
      return
    }
    if YouTubeMusic.videoID(url) != nil {
      decisionHandler(.cancel)
      choose(url, restore: false)
      return
    }
    if url.host == "accounts.google.com" {
      decisionHandler(.cancel)
      message = L(
        "Account sync requires Google authorization. Use Playlists → Import Takeout to bring your playlists into NOCTURNE.")
      return
    }
    guard url.scheme == "https", let host = url.host,
      [
        "music.youtube.com", "consent.youtube.com", "consent.google.com", "www.youtube.com",
        "youtube.com",
      ].contains(host)
    else {
      decisionHandler(.cancel)
      return
    }
    if action.targetFrame == nil {
      decisionHandler(.cancel)
      webView.load(action.request)
    } else {
      decisionHandler(.allow)
    }
  }
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) { report(error) }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    report(error)
  }
  private func report(_ error: Error) {
    let e = error as NSError
    if active && e.code != NSURLErrorCancelled
      && !(e.domain == WKError.errorDomain && e.code == 102)
    {
      message = error.localizedDescription
    }
  }
}
private struct CatalogSurface: NSViewRepresentable {
  let page: CatalogPage
  func makeNSView(context: Context) -> WKWebView { page.web }
  func updateNSView(_ view: WKWebView, context: Context) {}
}
