import SwiftUI

/// Keyless YouTube Music browse data (explore, charts, playlists, albums, artists),
/// read from the endpoint music.youtube.com itself uses and shown in native pages.
enum MusicBrowse {
  struct Link: Hashable {
    let title, subtitle: String
    let cover: URL?
    let id: String
    let params: String?
  }
  enum Item: Hashable {
    case track(Track)
    case link(Link)
  }
  struct Section: Identifiable {
    let id = UUID()
    let title: String
    var items: [Item]
    var tracks: [Track] { items.compactMap { if case .track(let t) = $0 { t } else { nil } } }
    var links: [Link] { items.compactMap { if case .link(let l) = $0 { l } else { nil } } }
  }
  struct Page {
    var title: String?
    var sections: [Section]
    var tracks: [Track] { sections.flatMap(\.tracks) }
  }

  static func text(_ value: Any?) -> String? {
    let d = value as? [String: Any]
    return d?["simpleText"] as? String
      ?? (d?["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
  }
  /// Depth-first search for a key; sorted so the result does not depend on dictionary order.
  static func first(_ key: String, in json: Any?) -> Any? {
    if let d = json as? [String: Any] {
      if let hit = d[key] { return hit }
      for k in d.keys.sorted() { if let hit = first(key, in: d[k]) { return hit } }
    } else if let a = json as? [Any] {
      for x in a { if let hit = first(key, in: x) { return hit } }
    }
    return nil
  }
  // Ids end up in the player page and request bodies, so only YouTube's own alphabet passes.
  static func valid(_ id: String?, video: Bool) -> String? {
    guard let id,
      id.range(of: video ? "^[A-Za-z0-9_-]{11}$" : "^[A-Za-z0-9_-]{2,120}$", options: .regularExpression)
        != nil
    else { return nil }
    return id
  }
  static func track(_ id: String, _ title: String, _ by: String, _ fallback: String?, _ length: String?)
    -> Item
  {
    let artist = by.components(separatedBy: " • ").first ?? ""
    let seconds = (length ?? "").split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
    return .track(
      Track(
        id: id, title: title, artist: artist.isEmpty ? fallback ?? "YouTube Music" : artist,
        duration: seconds, cover: URL(string: "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg")))
  }
  static func link(_ title: String, _ subtitle: String, _ source: Any?, _ endpoint: Any?) -> Item? {
    let e = endpoint as? [String: Any]
    guard let id = valid(e?["browseId"] as? String, video: false) else { return nil }
    let cover = (first("thumbnails", in: source) as? [[String: Any]])?.last?["url"] as? String
    return .link(
      Link(
        title: title, subtitle: subtitle, cover: cover.flatMap(URL.init(string:)), id: id,
        params: valid(e?["params"] as? String, video: false)))
  }
  static func item(_ json: [String: Any], artist: String?) -> Item? {
    if let r = json["musicResponsiveListItemRenderer"] as? [String: Any] {
      let cols = (r["flexColumns"] as? [[String: Any]] ?? []).map {
        text(($0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]) ?? ""
      }
      guard let title = cols.first, !title.isEmpty else { return nil }
      let sub = cols.dropFirst().first ?? ""
      if let id = valid(first("videoId", in: r) as? String, video: true) {
        return track(id, title, sub, artist, text(first("text", in: r["fixedColumns"])))
      }
      return link(title, sub, r, (r["navigationEndpoint"] as? [String: Any])?["browseEndpoint"])
    }
    if let r = json["musicTwoRowItemRenderer"] as? [String: Any], let title = text(r["title"]) {
      let nav = r["navigationEndpoint"] as? [String: Any]
      let sub = text(r["subtitle"]) ?? ""
      if let id = valid((nav?["watchEndpoint"] as? [String: Any])?["videoId"] as? String, video: true) {
        return track(id, title, sub, artist, nil)
      }
      return link(title, sub, r, nav?["browseEndpoint"])
    }
    if let r = json["musicNavigationButtonRenderer"] as? [String: Any], let title = text(r["buttonText"]) {
      return link(title, "", nil, (r["clickCommand"] as? [String: Any])?["browseEndpoint"])
    }
    return nil
  }
  static func sections(_ json: Any, artist: String?) -> [Section] {
    if let d = json as? [String: Any] {
      for name in [
        "musicCarouselShelfRenderer", "musicShelfRenderer", "musicPlaylistShelfRenderer", "gridRenderer",
      ] {
        guard let shelf = d[name] as? [String: Any] else { continue }
        let items = ((shelf["contents"] ?? shelf["items"]) as? [[String: Any]] ?? []).compactMap {
          item($0, artist: artist)
        }
        let title = text(first("title", in: shelf["header"]) ?? shelf["title"]) ?? ""
        return items.isEmpty ? [] : [Section(title: title, items: items)]
      }
      return d.keys.sorted().flatMap { sections(d[$0]!, artist: artist) }
    }
    return (json as? [Any])?.flatMap { sections($0, artist: artist) } ?? []
  }
  /// Continuation responses carry bare rows without a shelf around them.
  static func items(_ json: Any, artist: String?) -> [Item] {
    if let d = json as? [String: Any] {
      if let one = item(d, artist: artist) { return [one] }
      return d.keys.sorted().flatMap { items(d[$0]!, artist: artist) }
    }
    return (json as? [Any])?.flatMap { items($0, artist: artist) } ?? []
  }
  static func call(_ body: [String: Any]) async throws -> Any {
    var r = URLRequest(
      url: URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false")!,
      timeoutInterval: 15)
    r.httpMethod = "POST"
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var payload = body
    payload["context"] = [
      "client": [
        "clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00",
        "hl": Bundle.main.preferredLocalizations.first ?? "en",
        "gl": Locale.current.region?.identifier ?? "US",
      ]
    ]
    r.httpBody = try JSONSerialization.data(withJSONObject: payload)
    if let credentials {  // signed in: private playlists and the user's library become readable
      r.httpShouldHandleCookies = false
      r.setValue(credentials.cookie, forHTTPHeaderField: "Cookie")
      r.setValue(
        authorization(sapisid: credentials.sapisid, time: Int(Date().timeIntervalSince1970)),
        forHTTPHeaderField: "Authorization")
      r.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
      r.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
    }
    let (data, response) = try await URLSession.shared.data(for: r)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw Issue("YouTube Music could not load this page. It may be private or unavailable.")
    }
    return try JSONSerialization.jsonObject(with: data)
  }
  static func load(_ id: String, params: String? = nil) async throws -> Page {
    var body: [String: Any] = ["browseId": id]
    if let params { body["params"] = params }
    var json = try await call(body)
    let header = first("musicResponsiveHeaderRenderer", in: json) as? [String: Any]
    let artist = text(header?["straplineTextOne"])
    var page = Page(title: text(header?["title"]), sections: sections(json, artist: artist))
    // Playlists arrive 100 rows at a time. shortcut: stops at 3,000 tracks, raise if lists get longer.
    for _ in 0..<30 {
      guard !page.sections.isEmpty,
        let token = (first("continuationCommand", in: json) as? [String: Any])?["token"] as? String
      else { break }
      try Task.checkCancellation()
      json = try await call(["continuation": token])
      let more = items(json, artist: artist)
      if more.isEmpty { break }
      page.sections[page.sections.count - 1].items += more
    }
    return page
  }
}

struct OnlineRows: View {
  @ObservedObject var s: Session
  let tracks: [Track]
  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(Array(tracks.enumerated()), id: \.offset) { _, t in
        Button {
          s.select(t, in: tracks)
        } label: {
          HStack {
            Cover(track: t, size: 40)
            VStack(alignment: .leading) {
              Text(t.title).fontWeight(.medium)
              Text(t.artist).font(.caption).foregroundStyle(.secondary)
            }.lineLimit(1)
            Spacer()
            if t.duration > 0 {
              Text(stamp(t.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Image(systemName: "play.fill")
          }.padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("catalog.track." + t.id)
        Divider()
      }
    }
  }
}

/// Explore, Charts and any playlist, album, artist or genre page reached from them.
struct BrowsePage: View {
  @ObservedObject var s: Session
  let id: String
  var params: String?
  let title: String
  @State private var page: MusicBrowse.Page?
  @State private var issue: String?
  @State private var attempt = 0
  var body: some View {
    Group {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        if !s.trail.isEmpty {
          Button {
            s.route = s.trail.removeLast()
          } label: {
            Image(systemName: "chevron.left").font(.title2)
          }.buttonStyle(.plain).help("Back").accessibilityLabel("Back")
        }
        Text(L(page?.title ?? title)).font(.system(size: 33, weight: .bold)).tracking(-1.3)
        Spacer()
        if let page, id.hasPrefix("VL") || id.hasPrefix("MPRE"), !page.tracks.isEmpty {
          Button("Save as playlist") { s.savePlaylist(page.title ?? title, page.tracks) }
        }
      }
      if let issue {
        Text(issue).foregroundStyle(.secondary)
        Button("Retry") { attempt += 1 }
      } else if page == nil {
        ProgressView().controlSize(.small)
      } else if page?.sections.isEmpty == true {
        Text("No results found.").foregroundStyle(.secondary)
      }
      ForEach(page?.sections ?? []) { section in
        if !section.title.isEmpty { Text(section.title).font(.title2.bold()) }
        if !section.links.isEmpty {
          ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 15) {
              ForEach(section.links, id: \.self) { link in
                Button {
                  s.open(.browse(link.id, link.params, link.title))
                } label: {
                  if link.cover == nil {
                    Text(link.title).padding(.horizontal, 14).padding(.vertical, 9).background(
                      .primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                  } else {
                    VStack(alignment: .leading) {
                      Cover(track: Track(id: link.id, title: "", artist: "", cover: link.cover), size: 124)
                      Text(link.title).fontWeight(.semibold)
                      Text(link.subtitle).font(.caption).foregroundStyle(.secondary)
                    }.lineLimit(1).frame(width: 124, alignment: .leading)
                  }
                }.buttonStyle(.plain)
              }
            }
          }
        }
        if !section.tracks.isEmpty { OnlineRows(s: s, tracks: section.tracks) }
      }
    }.task(id: id + (params ?? "") + String(attempt)) {
      page = nil
      issue = nil
      do { page = try await MusicBrowse.load(id, params: params) } catch {
        if !Task.isCancelled { issue = error.localizedDescription }
      }
    }
  }
}
