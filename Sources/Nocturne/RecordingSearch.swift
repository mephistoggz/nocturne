import Foundation

enum RecordingSearch {
  struct AudioPage: Decodable {
    struct Row: Decodable {
      let strTrack: String?
      let strArtist: String?
      let strMusicVid: String?
      let strAlbum: String?
    }
    let track: [Row]?
  }

  static func audioTracks(_ endpoint: String, _ params: [String: String]) async throws -> [Track] {
    let url = URL(string: "https://www.theaudiodb.com/api/v1/json/123/" + endpoint)!
      .appending(queryItems: params.map { URLQueryItem(name: $0.key, value: $0.value) })
    let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8))
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Issue("TheAudioDB is unavailable.") }
    return try JSONDecoder().decode(AudioPage.self, from: data).track?.compactMap { row in
      guard let link = row.strMusicVid, let url = URL(string: link), let id = YouTubeMusic.videoID(url),
            let title = row.strTrack, let artist = row.strArtist else { return nil }
      return Track(id: id, title: title, artist: artist, album: row.strAlbum ?? "",
                   cover: URL(string: "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg"))
    } ?? []
  }

  static func audioSearch(_ term: String) async throws -> [Track] {
    for separator in [" - ", " – ", " — "] {
      let parts = term.components(separatedBy: separator)
      if parts.count == 2 { return try await audioTracks("searchtrack.php", ["s":parts[0], "t":parts[1]]) }
    }
    let artistResults = try await audioTracks("track-top10.php", ["s":term])
    if !artistResults.isEmpty { return artistResults }
    let words = term.split(whereSeparator: { $0.isWhitespace })
    for split in 1..<max(1,min(words.count,4)) {
      try Task.checkCancellation()
      let rows = try await audioTracks("searchtrack.php", [
        "s":words.prefix(split).joined(separator:" "), "t":words.dropFirst(split).joined(separator:" ")])
      if !rows.isEmpty { return rows }
    }
    return []
  }

  /// The keyless search endpoint youtube.com itself uses; "EgIQAQ==" limits results to videos.
  static func youtube(_ term: String) async throws -> [Track] {
    var r = URLRequest(
      url: URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false")!,
      timeoutInterval: 12)
    r.httpMethod = "POST"
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.httpBody = try JSONSerialization.data(withJSONObject: [
      "context": ["client": ["clientName": "WEB", "clientVersion": "2.20250101.00.00"]],
      "query": term, "params": "EgIQAQ==",
    ])
    let (data, response) = try await URLSession.shared.data(for: r)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Issue("YouTube search is unavailable.") }
    return youtubeTracks(try JSONSerialization.jsonObject(with: data))
  }
  /// Collects every videoRenderer wherever it sits, so layout changes in the response don't break parsing.
  static func youtubeTracks(_ json: Any) -> [Track] {
    func text(_ value: Any?) -> String? {
      let d = value as? [String: Any]
      return d?["simpleText"] as? String
        ?? (d?["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
    }
    if let d = json as? [String: Any] {
      if let v = d["videoRenderer"] as? [String: Any],
        let id = MusicBrowse.valid(v["videoId"] as? String, video: true),
        let title = text(v["title"])
      {
        let seconds = (text(v["lengthText"]) ?? "").split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
        return [Track(id: id, title: title, artist: text(v["ownerText"]) ?? "YouTube", duration: seconds,
                      cover: URL(string: "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg"))]
      }
      return d.values.flatMap(youtubeTracks)
    }
    return (json as? [Any])?.flatMap(youtubeTracks) ?? []
  }

  static func search(_ term: String) async throws -> [Track] {
    // YouTube first; the open indexes below only cover a small subset and stay as a fallback.
    if let found = try? await youtube(term), !found.isEmpty { return found }
    try Task.checkCancellation()
    async let wiki = try? OpenMusicIndex.search(term)
    async let audio = try? audioSearch(term)
    let (first, second) = await (wiki, audio)
    try Task.checkCancellation()
    guard first != nil || second != nil else { throw Issue("Search services are unavailable. Try the YouTube Music catalog.") }
    var ids = Set<String>()
    return ((first ?? []) + (second ?? [])).filter { ids.insert($0.id).inserted }
  }
}
