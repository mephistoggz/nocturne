import AVFoundation
import AppKit
import SwiftUI
import Testing
import WebKit

@testable import Nocturne

@Test func youtubeSearchParsing() throws {
  let json = try JSONSerialization.jsonObject(with: Data(#"""
    {"contents":[{"x":{"videoRenderer":{"videoId":"q71TncBWoEQ","title":{"runs":[{"text":"Arkadaşım Eşek"}]},
    "ownerText":{"runs":[{"text":"barismancotv"}]},"lengthText":{"simpleText":"2:41"}}}},{"videoRenderer":{"title":{}}}]}
    """#.utf8))
  let tracks = RecordingSearch.youtubeTracks(json)
  #expect(tracks.count == 1)
  #expect(tracks.first?.id == "q71TncBWoEQ" && tracks.first?.title == "Arkadaşım Eşek")
  #expect(tracks.first?.artist == "barismancotv" && tracks.first?.duration == 161)
}
@Test func browseParsing() throws {
  let json = try JSONSerialization.jsonObject(with: Data(#"""
    {"contents":[{"musicCarouselShelfRenderer":{"header":{"h":{"title":{"runs":[{"text":"Trend"}]}}},"contents":[
    {"musicResponsiveListItemRenderer":{"flexColumns":[
      {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Garson","navigationEndpoint":{"watchEndpoint":{"videoId":"zJY8z8v0xbo"}}}]}}},
      {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"İrem Derici"},{"text":" • 6,9 Mn"}]}}}],
      "fixedColumns":[{"musicResponsiveListItemFixedColumnRenderer":{"text":{"runs":[{"text":"3:05"}]}}}]}},
    {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Top 100"}]},"subtitle":{"runs":[{"text":"Liste"}]},
      "navigationEndpoint":{"browseEndpoint":{"browseId":"VLPL4fGSI1pDJn6rnJKpaAkK1XK8QUfa9KqP"}}}},
    {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Bad"}]},"navigationEndpoint":{"watchEndpoint":{"videoId":"x');alert(1)//"}}}}
    ]}}]}
    """#.utf8))
  let sections = MusicBrowse.sections(json, artist: nil)
  #expect(sections.count == 1 && sections[0].title == "Trend" && sections[0].items.count == 2)
  let track = try #require(sections[0].tracks.first)
  #expect(track.id == "zJY8z8v0xbo" && track.artist == "İrem Derici" && track.duration == 185)
  #expect(sections[0].links.first?.id == "VLPL4fGSI1pDJn6rnJKpaAkK1XK8QUfa9KqP")
  #expect(
    YouTubeMusic.browseID(URL(string: "https://music.youtube.com/playlist?list=PLabc_123")!)
      == "VLPLabc_123")
}
@Test func livePlaylistImport() async throws {
  guard ProcessInfo.processInfo.environment["NOCTURNE_LIVE_TEST"] == "1" else { return }
  let page = try await MusicBrowse.load("VLPLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI")
  #expect(page.title?.isEmpty == false)
  #expect(Set(page.tracks.map(\.id)).count > 100, "Continuation pages were not followed.")
  for id in ["FEmusic_explore", "FEmusic_charts"] {
    #expect(try await !MusicBrowse.load(id).sections.isEmpty)
  }
}
@Test func accountAuthorizationHeader() {
  #expect(
    MusicBrowse.authorization(sapisid: "abc", time: 1_700_000_000)
      == "SAPISIDHASH 1700000000_2f3ec011e870f3fbd0238c090c2062c208cead32")
}
@Test func lyricsParsing() {
  let lines = Lyrics.parse("[00:12.50] second\n[00:01.00][01:05.00]first\n[ar:Someone]\n[00:20.00]\nplain")
  #expect(lines.map(\.text) == ["first", "second", "first"])
  #expect(lines.map(\.time) == [1, 12.5, 65])
  #expect(Lyrics.current(lines, at: 0) == nil && Lyrics.current(lines, at: 13) == 1)
  #expect(
    Lyrics.query(Track(id: "x", title: "Barış Manço - Arkadaşım Eşek (HD) [Official]", artist: "barismancotv"))
      == "Barış Manço - Arkadaşım Eşek")
  #expect(Lyrics.query(Track(id: "x", title: "Stronger", artist: "Kanye West")) == "Kanye West Stronger")
}
@Test func liveLyrics() async {
  guard ProcessInfo.processInfo.environment["NOCTURNE_LIVE_TEST"] == "1" else { return }
  let lines = await Lyrics.fetch(Track(id: "x", title: "Stronger", artist: "Kanye West", duration: 312))
  #expect(lines.count > 20 && lines.first?.time != nil)
}
@Test func turkishStringsParse() throws {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../Resources/tr.lproj/Localizable.strings")
  let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
  #expect(table["Search"] == "Ara" && table.count > 150)
}
@Test func linksAndQueries() throws {
  let id = "jNQXAC9IVRw"
  for link in ["https://music.youtube.com/watch?v=" + id, "https://youtu.be/" + id + "?si=abc"] {
    #expect(YouTubeMusic.videoID(URL(string: link)!) == id)
  }
  for link in [
    "https://youtube.com.example.org/watch?v=" + id, "https://example.org/" + id,
    "https://youtu.be/bad", "http://youtu.be/" + id,
  ] {
    #expect(YouTubeMusic.videoID(URL(string: link)!) == nil)
  }
  let term = "Björk & strings #1"
  let query = URLComponents(url: YouTubeMusic().searchURL(term), resolvingAgainstBaseURL: false)?
    .queryItems
  #expect(query?.first?.value == term)
}
@Test func persistentLibrary() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: dir) }
  let file = dir.appendingPathComponent("test.sqlite")
  let a = Track(id: "a", title: "First", artist: "Artist")
  let b = Track(id: "b", title: "Second", artist: "Other")
  var data = LibraryData()
  data.add(a)
  data.add(a)
  data.add(b)
  data.favorites.insert(a.id)
  data.lists = [CollectionList(name: "Original", ids: ["b", "a"])]
  data.history = ["a"]
  data.searches = ["Artist"]
  data.selected = "b"
  try Database(at: file).save(data)
  let db = try Database(at: file)
  var restored = try db.read()
  #expect(restored.tracks.count == 2)
  #expect(restored.favorites == ["a"])
  #expect(restored.selected == "b")
  #expect(restored.resolve(restored.lists[0].ids) == [b, a])
  restored.lists[0].ids.swapAt(0, 1)
  restored.lists[0].name = "Renamed"
  try db.save(restored)
  #expect(try db.read().lists[0].ids == ["a", "b"])
  restored.lists.removeAll()
  try db.save(restored)
  #expect(try db.read().lists.isEmpty)
}
@Test @MainActor func nativePlaybackAndViews() async throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: dir) }
  let s = Session(directory: dir, systemCommands: false)
  let url = dir.appendingPathComponent("Silence.caf")
  let fmt = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
  do {
    let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 40000)!
    buffer.frameLength = 40000
    buffer.floatChannelData![0].initialize(repeating: 0, count: 40000)
    try file.write(from: buffer)
  }
  let t = try await LocalAudio.track(at: url, covers: dir)
  #expect(t.duration == 5)
  s.change { $0.add(t) }
  s.select(t, in: [t])
  for _ in 0..<50 where !s.playing { try await Task.sleep(for: .milliseconds(100)) }
  #expect(s.playing)
  if ProcessInfo.processInfo.environment["NOCTURNE_PROFILE"] == "1" {
    let start = Date()
    let cpu = clock()
    try await Task.sleep(for: .seconds(2))
    let percent = 100 * Double(clock() - cpu) / Double(CLOCKS_PER_SEC) / -start.timeIntervalSinceNow
    print(
      String(
        format: "Local playback test process CPU %.2f%%, elapsed %.3fs", percent,
        -start.timeIntervalSinceNow))
    #expect(s.head.seconds >= 1)
  }
  #expect(s.library.history == [t.id])
  s.seek(2)
  #expect(s.head.seconds == 2)
  s.toggle()
  try await Task.sleep(for: .milliseconds(200))
  #expect(!s.playing)
  s.favorite(t)
  #expect(s.library.favorites.contains(t.id))
  let list = CollectionList(name: "Session", ids: [t.id])
  s.change { $0.lists.append(list) }
  let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 980, height: 630), styleMask: [.titled, .resizable],
    backing: .buffered, defer: false)
  let host = NSHostingView(rootView: MainWindow(s: s))
  host.sizingOptions = []
  win.contentView = host
  for route: Route in [
    .home, .search, .explore, .charts, .recent, .songs, .albums, .artists, .artist(t.artist),
    .album("Test"), .playlists, .favorites, .list(list.id),
  ] {
    s.route = route
    host.layoutSubtreeIfNeeded()
    #expect(host.bounds.width >= 800)
  }
  win.setContentSize(NSSize(width: 820, height: 550))
  s.expanded = true
  host.layoutSubtreeIfNeeded()
  func checkWindow<V: View>(_ view: V, width: CGFloat, height: CGFloat) {
    let content = NSHostingView(rootView: view)
    content.sizingOptions = []
    win.contentView = content
    win.setContentSize(NSSize(width: width, height: height))
    win.display()
    #expect(content.bounds.width == width)
  }
  checkWindow(Mini(s: s), width: 360, height: 95)
  checkWindow(Preferences(s: s), width: 475, height: 560)
  let controller = TouchController(s: s)
  for layout in ["Minimal", "Standard", "Advanced"] {
    controller.attach(to: win, layout: layout, enabled: true)
    let bar = try #require(win.touchBar)
    for id in bar.defaultItemIdentifiers {
      #expect(controller.touchBar(bar, makeItemForIdentifier: id) != nil)
    }
  }
  controller.attach(to: win, layout: "Standard", enabled: false)
  #expect(win.touchBar == nil)
  s.stopEngine()
  let bad = Track(
    id: "missing", title: "Missing", artist: "Test", file: dir.appendingPathComponent("missing.wav")
  )
  s.select(bad, in: [bad])
  #expect(s.error != nil)
  #expect(!s.playing)
}
@Test func publicMetadata() async throws {
  guard ProcessInfo.processInfo.environment["NOCTURNE_LIVE_TEST"] == "1" else { return }
  let track = try await YouTubeMusic().resolve(URL(string: "https://youtu.be/jNQXAC9IVRw")!)
  #expect(track.title == "Me at the zoo")
  #expect(track.cover != nil)
}

@Test @MainActor func officialPlayerIntegration() async throws {
  guard ProcessInfo.processInfo.environment["NOCTURNE_PLAYER_TEST"] == "1" else { return }
  _ = NSApplication.shared
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: dir) }
  let session = Session(directory: dir, systemCommands: false)
  let track = try await session.provider.resolve(
    URL(string: "https://music.youtube.com/watch?v=dQw4w9WgXcQ")!)
  session.change { $0.add(track) }
  let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1024, height: 700), styleMask: [.titled],
    backing: .buffered, defer: false)
  win.contentView = NSHostingView(rootView: MainWindow(s: session))
  win.orderFront(nil)
  defer {
    session.stopEngine()
    win.orderOut(nil)
  }
  let windows = Set(NSApp.windows.filter { $0.isVisible }.map(\.windowNumber))
  session.select(track, in: [track])
  let engine = try #require(session.inlinePlayer)
  for _ in 0..<100 where !session.webReady && session.error == nil {
    try await Task.sleep(for: .milliseconds(200))
  }
  try #require(
    session.webReady, "\(session.error ?? "The official player did not signal readiness.")")
  engine.command("mute")
  #expect(engine.web.window === win)
  #expect(Set(NSApp.windows.filter { $0.isVisible }.map(\.windowNumber)) == windows)
  for _ in 0..<60 where session.head.seconds < 1 && session.error == nil {
    try await Task.sleep(for: .milliseconds(200))
  }
  #expect(
    session.head.seconds >= 1,
    "\(session.error ?? "Playback requires a gesture inside the player.")")
  // Music must keep playing with the app hidden or its window off screen.
  win.orderOut(nil)
  let before = session.head.seconds
  try await Task.sleep(for: .seconds(4))
  #expect(session.head.seconds >= before + 2, "Playback stopped in the background.")
}

@Test @MainActor func renderHome() async throws {
  guard let destination = ProcessInfo.processInfo.environment["NOCTURNE_PREVIEW"] else { return }
  _ = NSApplication.shared
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: dir) }
  let s = Session(directory: dir, systemCommands: false)
  let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1050, height: 650), styleMask: [.titled, .resizable],
    backing: .buffered, defer: false)
  win.appearance = NSAppearance(named: .darkAqua)
  let host = NSHostingView(rootView: MainWindow(s: s).environment(\.colorScheme, .dark))
  host.sizingOptions = []
  win.contentView = host
  win.orderFront(nil)
  defer { win.orderOut(nil) }
  // NOCTURNE_PREVIEW_ROUTE=explore|charts|lyrics renders that page instead (needs the network).
  let page = ProcessInfo.processInfo.environment["NOCTURNE_PREVIEW_ROUTE"]
  if page == "lyrics" {
    s.current = Track(
      id: "PsO6ZnUZI0g", title: "Stronger", artist: "Kanye West", duration: 312,
      cover: URL(string: "https://i.ytimg.com/vi/PsO6ZnUZI0g/hqdefault.jpg"))
    s.expanded = true
    s.head.seconds = 34
  } else if let page {
    s.route = page == "charts" ? .charts : .explore
  }
  try await Task.sleep(for: .milliseconds(page == nil ? 450 : 6000))
  win.display()
  let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: rep)
  let png = try #require(rep.representation(using: .png, properties: [:]))
  try png.write(to: URL(fileURLWithPath: destination))
}

@Test func takeoutRoundTrip() async throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }
  let metadata = "Playlist ID,Playlist (Original) Title\r\nPL123456789012345,\"Gece, müzik\"\r\n"
  try metadata.write(
    to: dir.appendingPathComponent("playlists.csv"), atomically: true, encoding: .utf8)
  try "Video ID,Playlist Video Creation Timestamp\r\ndQw4w9WgXcQ,2020\r\njNQXAC9IVRw,2021\r\n"
    .write(to: dir.appendingPathComponent("Gece, müzik.csv"), atomically: true, encoding: .utf8)
  let imported = try await Takeout.read([dir])
  let database = try Database(at: dir.appendingPathComponent("Library.sqlite"))
  var data = LibraryData()
  data.mergeTakeout(imported)
  data.mergeTakeout(imported)
  try database.save(data)
  let stored = try database.read()
  #expect(stored.lists.count == 1)
  #expect(stored.lists.first?.name == "Gece, müzik")
  #expect(stored.lists.first?.ids == ["dQw4w9WgXcQ", "jNQXAC9IVRw"])
  #expect(stored.tracks.count == 2)
}

@Test @MainActor func inAppCatalogSelection() async throws {
  guard ProcessInfo.processInfo.environment["NOCTURNE_CATALOG_TEST"] == "1" else { return }
  _ = NSApplication.shared
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: dir) }
  let session = Session(directory: dir, systemCommands: false)
  let page = CatalogPage()
  page.session = session
  let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled],
    backing: .buffered, defer: false)
  win.contentView = page.web
  win.orderFront(nil)
  defer {
    page.deactivate()
    session.stopEngine()
    win.orderOut(nil)
  }
  let url = session.provider.searchURL("Mr.Kitty After Dark")
  page.open(url)
  // YouTube uses both links and clickable title elements in its result layouts.
  let selector = "Array.from(document.querySelectorAll('a,yt-formatted-string')).find(e=>e.offsetWidth>0 && e.textContent.trim().toLowerCase()==='mr.kitty - after dark')"
  var found=false
  for _ in 0..<90 {
    if (try? await page.web.evaluateJavaScript("Boolean("+selector+")") as? Bool)==true {found=true;break}
    try await Task.sleep(for:.milliseconds(250))
  }
  try #require(found)
  let play = """
    (()=>{const title=(\(selector));const row=title.closest('ytmusic-responsive-list-item-renderer,ytmusic-card-shelf-renderer,ytmusic-two-row-item-renderer'); const target=row?.querySelector('ytmusic-play-button-renderer button,ytmusic-play-button-renderer, a[href*="watch?v="]') || title.closest('a') || title;target.click();return true})()
    """
  _ = try await page.web.evaluateJavaScript(play)
  for _ in 0..<60 where session.current==nil {try await Task.sleep(for:.milliseconds(250))}
  #expect(session.current?.title.localizedCaseInsensitiveContains("After Dark") == true)
  #expect(session.library.tracks.contains(where: { $0.id == session.current?.id }))
}

@Test @MainActor func nativeSearchToInlinePlayback() async throws {
  guard ProcessInfo.processInfo.environment["NOCTURNE_NATIVE_TEST"] == "1" else { return }
  _ = NSApplication.shared
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: dir) }
  let s = Session(directory: dir, systemCommands: false)
  s.route = .search
  let host = NSHostingView(rootView: MainWindow(s: s))
  let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled],
    backing: .buffered, defer: false)
  win.contentView = host
  win.orderFront(nil)
  defer {
    s.stopEngine()
    win.orderOut(nil)
  }
  let windows = Set(NSApp.windows.filter { $0.isVisible }.map(\.windowNumber))
  s.query = "Never Gonna Give You Up"
  win.makeKeyAndOrderFront(nil)
  // At the fixed test window size the second search row sits 290 pt below
  // the content's top edge. Deliver ordinary AppKit mouse events to the host.
  for _ in 0..<40 where s.inlinePlayer == nil {
    try await Task.sleep(for: .milliseconds(500))
    host.layoutSubtreeIfNeeded()
    let point = host.convert(
      NSPoint(x: 360, y: host.isFlipped ? 290 : host.bounds.height - 290), to: nil)
    for kind: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
      let event = try #require(
        NSEvent.mouseEvent(
          with: kind, location: point, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
          context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
      win.sendEvent(event)
    }
  }
  #expect(s.current?.title.localizedCaseInsensitiveContains("gonna give you up") == true)
  for _ in 0..<80 where s.head.seconds < 1 {
    s.inlinePlayer?.command("mute")
    try await Task.sleep(for: .milliseconds(200))
  }
  #expect(s.inlinePlayer?.web.window === win)
  #expect(s.head.seconds >= 1)
  #expect(Set(NSApp.windows.filter { $0.isVisible }.map(\.windowNumber)) == windows)
}

@Test func googlePagingAndConsent() async throws {
  final class Stub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      let url = request.url!
      let json: String
      if url.lastPathComponent == "playlists" {
        json = #"{"items":[{"id":"PL_demo","snippet":{"title":"Deneme"}}]}"#
      } else if url.absoluteString.contains("pageToken=") {
        json = #"{"items":[{"snippet":{"title":"Second","resourceId":{"videoId":"jNQXAC9IVRw"}}}]}"#
      } else {
        json =
          #"{"nextPageToken":"page2","items":[{"snippet":{"title":"First","resourceId":{"videoId":"dQw4w9WgXcQ"}}}]}"#
      }
      let status =
        request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only" ? 200 : 401
      client?.urlProtocol(
        self,
        didReceive: HTTPURLResponse(
          url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
        cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(json.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
  }
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [Stub.self]
  let lists = try await GoogleCatalog(http: URLSession(configuration: config)).playlists(
    "test-only")
  #expect(lists.first?.tracks.map(\.id) == ["dQw4w9WgXcQ", "jNQXAC9IVRw"])
  let consent = GoogleOAuth.consent(
    .init(client_id: "demo.apps.googleusercontent.com", client_secret: nil),
    redirect: "http://127.0.0.1:1234/oauth2callback", state: "test-state", verifier: "test-verifier"
  )
  let items = URLComponents(url: consent, resolvingAgainstBaseURL: false)?.queryItems
  #expect(items?.first(where: { $0.name == "scope" })?.value == GoogleOAuth.scope)
  #expect(items?.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
}

@Test func supplementalRecordingIndex() async throws {
  guard ProcessInfo.processInfo.environment["NOCTURNE_LIVE_TEST"] == "1" else { return }
  let tracks = try await RecordingSearch.audioSearch("Daft Punk Get Lucky")
  #expect(tracks.contains { $0.artist == "Daft Punk" && $0.title == "Get Lucky" })
}
