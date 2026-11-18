import AVFoundation
import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers

enum Route: Hashable {
  case home, search, explore, charts, recent, songs, albums, artists, favorites, playlists
  case accountList(String)
  case online(URL)
  case browse(String, String?, String)  // browse id, params, title
  case list(UUID)
  case album(String)
  case artist(String)
}
final class Playhead: ObservableObject { @Published var seconds = 0.0 }
@MainActor final class Session: NSObject, ObservableObject {
  static let shared = Session()
  nonisolated static let directory = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NOCTURNE")
  let provider: any MusicProvider = YouTubeMusic()
  let account = AccountSync()
  let head = Playhead()
  let player = AVPlayer()
  private var database: Database?
  @Published private(set) var library = LibraryData()
  @Published var route: Route = .home
  var trail: [Route] = []  // pages to return to with Back
  func open(_ next: Route) {
    trail.append(route)
    route = next
  }
  func savePlaylist(_ name: String, _ tracks: [Track]) {
    var seen = Set<String>()
    let unique = tracks.filter { seen.insert($0.id).inserted }
    let list = CollectionList(name: name, ids: unique.map(\.id))
    change { data in
      let known = Set(data.tracks.map(\.id))
      data.tracks += unique.filter { !known.contains($0.id) }
      data.lists.append(list)
    }
    if library.lists.contains(where: { $0.id == list.id }) { route = .list(list.id) }
  }
  @Published var lastError: String?
  @Published var error: String? { didSet { if let error { lastError = error } } }
  @Published var current: Track?
  @Published var webReady = false
  @Published var playing = false
  @Published var queue: [Track] = []
  @Published var expanded = false
  @Published var queueVisible = false
  @Published var naming = false
  @Published var editingList: UUID?
  @Published var adding = false
  @Published var busy = false
  @Published var query = ""
  @Published var shuffle = UserDefaults.standard.bool(forKey: "shuffle") {
    didSet { UserDefaults.standard.set(shuffle, forKey: "shuffle") }
  }
  @Published var repeatMode = UserDefaults.standard.integer(forKey: "repeat") {
    didSet { UserDefaults.standard.set(repeatMode, forKey: "repeat") }
  }
  @Published var volume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.75 {
    didSet {
      player.volume = Float(volume)
      inlinePlayer?.command("setVolume", volume * 100)
      UserDefaults.standard.set(volume, forKey: "volume")
    }
  }
  private var status: NSKeyValueObservation?
  private var itemStatus: NSKeyValueObservation?
  private var time: Any?
  private var ended: NSObjectProtocol?
  private var recorded = false
  @Published private(set) var inlinePlayer: InlinePlayer?
  private var recentSteps: [String] = []
  init(directory: URL = Session.directory, systemCommands: Bool = true) {
    super.init()
    do {
      let db = try Database(at: directory.appendingPathComponent("Library.sqlite"))
      library = try db.read()
      database = db
      if let id = library.selected {
        current = library.tracks.first { $0.id == id }
        queue = current.map { [$0] } ?? []
      }
    } catch { self.error = error.localizedDescription }
    player.volume = Float(volume)
    status = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      Task { @MainActor in self?.updatePlaying() }
    }
    if systemCommands {
      configureMedia()
      account.restore(self)
      if UserDefaults.standard.string(forKey: "startPage") == "Songs" { route = .songs }
    }
  }
  func change(_ operation: (inout LibraryData) -> Void) {
    do {
      guard let database else { throw Issue("Library storage is unavailable.") }
      var next = library
      operation(&next)
      try database.save(next)
      library = next
    } catch { self.error = error.localizedDescription }
  }
  func savePage(_ url: URL, name: String, kind: String) {
    let canonical = YouTubeMusic.canonicalPage(url)
    change { data in
      var pages = data.pages ?? []
      pages.removeAll { YouTubeMusic.canonicalPage($0.url) == canonical }
      pages.append(SavedPage(url: canonical, name: name, kind: kind))
      data.pages = pages
    }
  }
  func favorite(_ track: Track) {
    change { data in
      if !data.favorites.insert(track.id).inserted { data.favorites.remove(track.id) }
    }
    account.like(track, library.favorites.contains(track.id))  // no-op unless signed in
  }
  func removeTrack(_ track: Track) {
    change { d in
      d.tracks.removeAll { $0.id == track.id }
      d.history.removeAll { $0 == track.id }
      d.favorites.remove(track.id)
      for index in d.lists.indices { d.lists[index].ids.removeAll { $0 == track.id } }
      if d.selected == track.id { d.selected = nil }
    }
    guard !library.tracks.contains(where: { $0.id == track.id }) else { return }
    if current?.id == track.id {
      stopEngine()
      current = nil
    }
    queue.removeAll { $0.id == track.id }
    if let cover = track.cover, cover.isFileURL,
      cover.deletingLastPathComponent().standardizedFileURL
        == Self.directory.appendingPathComponent("Artwork").standardizedFileURL
    {
      try? FileManager.default.removeItem(at: cover)
    }
  }
  func recordSearch(_ term: String) {
    change {
      $0.searches.removeAll { $0 == term }
      $0.searches.insert(term, at: 0)
      $0.searches = Array($0.searches.prefix(12))
    }
  }
  func importFiles() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.audio]
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    let urls = panel.urls
    Task {
      var tracks: [Track] = []
      var failures: [String] = []
      busy = true
      defer { busy = false }
      for url in urls {
        if library.tracks.contains(where: { $0.file == url }) { continue }
        do {
          tracks.append(
            try await LocalAudio.track(
              at: url, covers: Self.directory.appendingPathComponent("Artwork")))
        } catch { failures.append(url.lastPathComponent + " — " + error.localizedDescription) }
      }
      change { data in tracks.forEach { data.add($0) } }
      route = .songs
      if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
  }
  func select(_ track: Track, in tracks: [Track], remember: Bool = true) {
    if remember, let previous = current, previous != track {
      recentSteps.append(previous.id)
      recentSteps = Array(recentSteps.suffix(100))
    }
    stopEngine()
    current = track
    queue = tracks.contains(where: { $0.id == track.id }) ? tracks : [track]
    change {
      $0.add(track)
      $0.selected = track.id
    }
    if let url = track.file {
      guard FileManager.default.isReadableFile(atPath: url.path) else {
        error = L("The audio file is missing. Restore it to") + " " + url.path
        return
      }
      let item = AVPlayerItem(url: url)
      itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
        Task { @MainActor in
          guard let self, self.player.currentItem === item, item.status == .failed else { return }
          self.stopEngine()
          self.error = item.error?.localizedDescription ?? L("Playback failed.")
        }
      }
      ended = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.player.currentItem === item else { return }
          if self.repeatMode == 2 {
            self.seek(0)
            self.player.play()
          } else if UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true {
            self.next()
          }
        }
      }
      player.replaceCurrentItem(with: item)
      time = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
      ) { [weak self] t in
        Task { @MainActor in
          guard let self, self.player.currentItem === item, t.seconds.isFinite else { return }
          self.head.seconds = max(0, t.seconds)
        }
      }
      player.play()
    } else {
      if track.title == track.id {
        Task {
          guard let resolved = try? await provider.resolve(track.watch),
            library.tracks.contains(where: { $0.id == resolved.id })
          else { return }
          change { $0.add(resolved) }
          if current?.id == resolved.id {
            var updated = resolved
            updated.duration = current?.duration ?? 0
            current = updated
            publishMedia()
          }
          queue = queue.map { $0.id == resolved.id ? resolved : $0 }
        }
      }
      inlinePlayer = InlinePlayer(track: track, session: self)
    }
  }
  func stopEngine() {
    itemStatus = nil
    if let time {
      player.removeTimeObserver(time)
      self.time = nil
    }
    if let ended {
      NotificationCenter.default.removeObserver(ended)
      self.ended = nil
    }
    player.pause()
    player.replaceCurrentItem(with: nil)
    inlinePlayer?.close()
    inlinePlayer = nil
    recorded = false
    playing = false
    head.seconds = 0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }
  func toggle() {
    guard let current else { return }
    if current.video != nil, let engine = inlinePlayer, engine.ready {
      engine.command(playing ? "pauseVideo" : "playVideo")
    } else if player.currentItem == nil {
      select(current, in: queue)
    } else if playing {
      player.pause()
    } else {
      if current.duration > 0 && head.seconds >= current.duration - 0.1 { seek(0) }
      player.play()
    }
  }
  func next() {
    guard let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
    if shuffle, let pick = queue.filter({ $0.id != current.id }).randomElement() {
      select(pick, in: queue)
    } else if index + 1 < queue.count {
      select(queue[index + 1], in: queue)
    } else if repeatMode == 1, let first = queue.first {
      select(first, in: queue)
    } else {
      player.pause()
    }
  }
  func previous() {
    if head.seconds > 3 {
      seek(0)
      return
    }
    if let id = recentSteps.popLast(), let last = library.tracks.first(where: { $0.id == id }) {
      select(last, in: queue, remember: false)
    } else if let current, let i = queue.firstIndex(where: { $0.id == current.id }), i > 0 {
      select(queue[i - 1], in: queue, remember: false)
    } else {
      seek(0)
    }
  }
  func seek(_ value: Double) {
    guard player.currentItem != nil || webReady, value.isFinite else { return }
    let t = max(0, min(current?.duration ?? 0, value))
    if webReady {
      inlinePlayer?.command("seekTo", t)
    } else {
      player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
    }
    head.seconds = t
    publishMedia()
  }
  private func updatePlaying() {
    guard current?.file != nil else { return }
    webPlaying(player.timeControlStatus == .playing)
  }
  func finishedVideo() {
    if repeatMode == 2 {
      seek(0)
      inlinePlayer?.command("playVideo")
    } else if UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true {
      next()
    }
  }
  func webPlaying(_ value: Bool) {
    playing = value
    if playing, !recorded, let current {
      recorded = true
      change {
        $0.history.removeAll { $0 == current.id }
        $0.history.insert(current.id, at: 0)
        $0.history = Array($0.history.prefix(300))
      }
    }
    publishMedia()
  }
  func publishMedia() {
    guard player.currentItem != nil || webReady, let t = current else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      MPNowPlayingInfoCenter.default().playbackState = .stopped
      return
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: t.title, MPMediaItemPropertyArtist: t.artist,
      MPMediaItemPropertyAlbumTitle: t.album, MPMediaItemPropertyPlaybackDuration: t.duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: head.seconds,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
    ]
    MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
  }
  private func configureMedia() {
    let c = MPRemoteCommandCenter.shared()
    func bind(_ command: MPRemoteCommand, _ action: @escaping @MainActor (Session) -> Void) {
      command.addTarget { [weak self] _ in
        Task { @MainActor in if let self { action(self) } }
        return .success
      }
    }
    bind(c.togglePlayPauseCommand) { $0.toggle() }
    bind(c.playCommand) { if !$0.playing { $0.toggle() } }
    bind(c.pauseCommand) {
      if $0.webReady { $0.inlinePlayer?.command("pauseVideo") } else { $0.player.pause() }
    }
    bind(c.nextTrackCommand) { $0.next() }
    bind(c.previousTrackCommand) { $0.previous() }
    c.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      Task { @MainActor in self?.seek(event.positionTime) }
      return .success
    }
  }
}
