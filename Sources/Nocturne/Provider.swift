import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

protocol MusicProvider {
  func resolve(_ link: URL) async throws -> Track
  func searchURL(_ query: String) -> URL
}
private actor RequestGate {
  static let shared = RequestGate()
  private var next = ContinuousClock.now
  func acquire() async throws {
    let start = max(ContinuousClock.now, next)
    next = start.advanced(by: .milliseconds(500))
    try await ContinuousClock().sleep(until: start)
    try Task.checkCancellation()
  }
}
struct YouTubeMusic: MusicProvider {
  func searchURL(_ query: String) -> URL {
    URL(string: "https://music.youtube.com/search")!.appending(queryItems: [
      .init(name: "q", value: query)
    ])
  }
  static func videoID(_ url: URL) -> String? {
    guard url.scheme == "https", let host = url.host?.lowercased() else { return nil }
    let id: String?
    if host == "youtu.be" {
      id = url.lastPathComponent
    } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(
      host), url.path == "/watch"
    {
      id =
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
          $0.name == "v"
        }?.value
    } else {
      return nil
    }
    guard let id, id.utf8.count == 11,
      id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    else { return nil }
    return id
  }
  static func canonicalPage(_ url: URL) -> URL {
    if let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(
      where: { $0.name == "list" })?.value,
      !list.isEmpty, url.path == "/playlist"
    {
      return URL(string: "https://music.youtube.com/playlist")!.appending(queryItems: [
        .init(name: "list", value: list)
      ])
    }
    return url
  }
  /// The browse id the native pages load for a shared playlist, album or artist link.
  static func browseID(_ url: URL) -> String? {
    guard pageKind(url) != nil else { return nil }
    if url.path == "/playlist" {
      let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
        $0.name == "list"
      })?.value
      return MusicBrowse.valid(list.map { "VL" + $0 }, video: false)
    }
    return MusicBrowse.valid(url.lastPathComponent, video: false)
  }
  static func pageKind(_ url: URL) -> String? {
    guard url.scheme == "https",
      url.host?.lowercased() == "music.youtube.com"
        || (["www.youtube.com", "youtube.com"].contains(url.host?.lowercased() ?? "")
          && url.path == "/playlist"),
      url.user == nil,
      url.password == nil
    else { return nil }
    let parts = url.pathComponents
    if parts.count == 3, parts[1] == "channel", !parts[2].isEmpty { return "Artist" }
    if parts.count == 3, parts[1] == "browse", parts[2].hasPrefix("MPRE") { return "Album" }
    if parts.count == 3, parts[1] == "browse", parts[2].hasPrefix("UC") { return "Artist" }
    if url.path == "/playlist",
      let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
        $0.name == "list"
      })?.value, !list.isEmpty
    {
      return list.hasPrefix("OLAK5uy") ? "Album" : "Playlist"
    }
    return nil
  }
  struct Metadata: Decodable {
    let title, author_name: String
    let thumbnail_url: URL?
  }
  func resolve(_ link: URL) async throws -> Track {
    guard let id = Self.videoID(link) else {
      throw Issue("Paste a YouTube Music song link or a YouTube watch link.")
    }
    let endpoint = URL(string: "https://www.youtube.com/oembed")!.appending(queryItems: [
      .init(name: "url", value: "https://www.youtube.com/watch?v=" + id),
      .init(name: "format", value: "json"),
    ])
    for attempt in 0...1 {
      try await RequestGate.shared.acquire()
      let (data, response) = try await URLSession.shared.data(
        for: URLRequest(url: endpoint, timeoutInterval: 12))
      let status = (response as? HTTPURLResponse)?.statusCode
      if status == 200 {
        let meta = try JSONDecoder().decode(Metadata.self, from: data)
        guard !meta.title.isEmpty else { throw Issue("YouTube returned an empty title.") }
        return Track(id: id, title: meta.title, artist: meta.author_name, cover: meta.thumbnail_url)
      }
      if attempt == 0, let status, (500...599).contains(status) {
        try await Task.sleep(for: .seconds(1))
      } else {
        throw Issue(
          status == 429
            ? "YouTube is receiving too many requests. Try again later."
            : "YouTube could not share this track. It may be private, unavailable, or restricted.")
      }
    }
    throw Issue("The request failed.")
  }
}

enum Art {
  static let cache: NSCache<NSURL, CGImage> = {
    let cache = NSCache<NSURL, CGImage>()
    cache.totalCostLimit = 20 * 1024 * 1024
    cache.countLimit = 128
    return cache
  }()
  static func image(_ url: URL?) async -> CGImage? {
    guard let url else { return nil }
    if let hit = cache.object(forKey: url as NSURL) { return hit }
    do {
      let data: Data
      if url.isFileURL {
        data = try Data(contentsOf: url)
      } else {
        data = try await URLSession.shared.data(from: url).0
      }
      try Task.checkCancellation()
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let cg = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
          ] as CFDictionary)
      else { return nil }
      cache.setObject(cg, forKey: url as NSURL, cost: cg.bytesPerRow * cg.height)
      return cg
    } catch { return nil }
  }
}
enum LocalAudio {
  static func track(at url: URL, covers: URL) async throws -> Track {
    let asset = AVURLAsset(url: url)
    guard try await asset.load(.isPlayable),
      !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
    else { throw Issue("Cannot play " + url.lastPathComponent) }
    let meta = try await asset.load(.commonMetadata)
    func value(_ key: AVMetadataKey) async -> String? {
      try? await meta.first { $0.commonKey == key }?.load(.stringValue)
    }
    let seconds = try await asset.load(.duration).seconds
    var cover: URL?
    if let pic = try? await meta.first(where: { $0.commonKey == .commonKeyArtwork })?.load(
      .dataValue)
    {
      try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
      let dest = covers.appendingPathComponent(UUID().uuidString)
      try pic.write(to: dest, options: .atomic)
      cover = dest
    }
    return await Track(
      id: url.standardizedFileURL.absoluteString,
      title: value(.commonKeyTitle) ?? url.deletingPathExtension().lastPathComponent,
      artist: value(.commonKeyArtist) ?? "Unknown artist", album: value(.commonKeyAlbumName) ?? "",
      duration: seconds.isFinite ? max(0, seconds) : 0, file: url, cover: cover)
  }
}
